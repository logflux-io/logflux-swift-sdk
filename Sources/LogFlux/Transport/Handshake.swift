import CryptoKit
import Foundation

enum HandshakeError: Error {
    case invalidURL
    case initFailed(Int, String?)
    case completeFailed(Int, String?)
    case noKeyID
    case networkError(Error)
}

/// Two-phase handshake with the LogFlux ingestor.
/// Phase 1: Get server RSA public key
/// Phase 2: Send RSA-encrypted AES key, receive key_id
enum Handshake {

    struct Result {
        let aesKey: SymmetricKey
        let keyID: String
        let maxBatchSize: Int
    }

    /// Perform the full handshake. Returns the AES key, key ID, and server limits.
    static func perform(ingestorURL: String, apiKey: String, timeout: TimeInterval = 15) async throws -> Result {
        let baseURL = ingestorURL.hasSuffix("/") ? String(ingestorURL.dropLast()) : ingestorURL

        // Phase 1: Get RSA public key
        let initResponse = try await handshakeInit(baseURL: baseURL, apiKey: apiKey, timeout: timeout)

        guard let pubKeyPEM = initResponse.data?.public_key else {
            throw HandshakeError.initFailed(0, "No public key in response")
        }

        let maxBatchSize = initResponse.data?.max_batch_size ?? 100

        // Generate AES-256 key
        let aesKey = AESEncryptor.generateKey()
        let aesKeyData = AESEncryptor.exportKey(aesKey)

        // RSA-OAEP encrypt the AES key
        let encryptedSecret = try RSAHelper.encryptWithPublicKey(
            aesKeyData: aesKeyData,
            pemPublicKey: pubKeyPEM
        )

        // Phase 2: Send encrypted key
        let completeResponse = try await handshakeComplete(
            baseURL: baseURL,
            apiKey: apiKey,
            encryptedSecret: encryptedSecret,
            timeout: timeout
        )

        guard let keyID = completeResponse.data?.key_id, !keyID.isEmpty else {
            throw HandshakeError.noKeyID
        }

        return Result(aesKey: aesKey, keyID: keyID, maxBatchSize: maxBatchSize)
    }

    // MARK: - Phases

    private static func handshakeInit(baseURL: String, apiKey: String, timeout: TimeInterval) async throws -> HandshakeInitResponse {
        guard let url = URL(string: "\(baseURL)/v1/handshake/init") else {
            throw HandshakeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout

        let body = HandshakeInitRequest(api_key: apiKey)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw HandshakeError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw HandshakeError.networkError(
                NSError(domain: "Handshake", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
            )
        }

        guard http.statusCode == 200 else {
            let errorBody = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw HandshakeError.initFailed(http.statusCode, errorBody?.error?.message)
        }

        return try JSONDecoder().decode(HandshakeInitResponse.self, from: data)
    }

    private static func handshakeComplete(
        baseURL: String,
        apiKey: String,
        encryptedSecret: String,
        timeout: TimeInterval
    ) async throws -> HandshakeCompleteResponse {
        guard let url = URL(string: "\(baseURL)/v1/handshake/complete") else {
            throw HandshakeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout

        let body = HandshakeCompleteRequest(api_key: apiKey, encrypted_secret: encryptedSecret)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw HandshakeError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw HandshakeError.networkError(
                NSError(domain: "Handshake", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
            )
        }

        guard http.statusCode == 200 else {
            let errorBody = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw HandshakeError.completeFailed(http.statusCode, errorBody?.error?.message)
        }

        return try JSONDecoder().decode(HandshakeCompleteResponse.self, from: data)
    }
}
