import Foundation

enum BatchSendError: Error {
    case invalidURL
    case authenticationRequired  // 401/403 -> re-handshake
    case rateLimited(retryAfter: TimeInterval?)
    case quotaExceeded(category: String?)
    case serverError(Int, String?)
    case networkError(Error)
}

/// Response body size limit to prevent unbounded reads.
private let maxResponseSize = 1_048_576 // 1 MiB

/// Sends batches of encrypted entries to the ingestor using multipart/mixed.
enum BatchSender {

    /// Send a multipart/mixed request to POST /v1/ingest.
    static func send(
        body: Data,
        contentType: String,
        ingestorURL: String,
        apiKey: String,
        timeout: TimeInterval = 30
    ) async throws {
        let baseURL = ingestorURL.hasSuffix("/") ? String(ingestorURL.dropLast()) : ingestorURL
        guard let url = URL(string: "\(baseURL)/v1/ingest") else {
            throw BatchSendError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw BatchSendError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw BatchSendError.networkError(
                NSError(domain: "BatchSender", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
            )
        }

        // Limit response body read
        let responseData = data.prefix(maxResponseSize)

        switch http.statusCode {
        case 200...299:
            return // Success
        case 401, 403:
            throw BatchSendError.authenticationRequired
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Double($0) }
            throw BatchSendError.rateLimited(retryAfter: retryAfter)
        case 507:
            // Quota exceeded - extract category if possible
            let errorBody = try? JSONDecoder().decode(ErrorResponse.self, from: Data(responseData))
            throw BatchSendError.quotaExceeded(category: errorBody?.error?.message)
        default:
            let errorBody = try? JSONDecoder().decode(ErrorResponse.self, from: Data(responseData))
            throw BatchSendError.serverError(http.statusCode, errorBody?.error?.message)
        }
    }
}
