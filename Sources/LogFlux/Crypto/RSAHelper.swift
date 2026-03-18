import Foundation
import Security

enum RSAError: Error {
    case invalidPEMFormat
    case keyCreationFailed(OSStatus)
    case encryptionFailed(Error)
}

/// RSA-OAEP-SHA256 operations for the handshake key exchange.
enum RSAHelper {

    /// Encrypt the AES key with the server's RSA public key using OAEP-SHA256.
    /// Returns base64-encoded ciphertext.
    static func encryptWithPublicKey(
        aesKeyData: Data,
        pemPublicKey: String
    ) throws -> String {
        let secKey = try parsePublicKey(pem: pemPublicKey)

        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(
            secKey,
            .rsaEncryptionOAEPSHA256,
            aesKeyData as CFData,
            &error
        ) else {
            if let err = error?.takeRetainedValue() {
                throw RSAError.encryptionFailed(err)
            }
            throw RSAError.encryptionFailed(
                NSError(domain: "RSAHelper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Encryption returned nil"])
            )
        }

        return (encrypted as Data).base64EncodedString()
    }

    /// Parse a PEM-encoded RSA public key into a SecKey.
    private static func parsePublicKey(pem: String) throws -> SecKey {
        // Strip PEM headers and whitespace
        let stripped = pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard let derData = Data(base64Encoded: stripped) else {
            throw RSAError.invalidPEMFormat
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(derData as CFData, attributes as CFDictionary, &error) else {
            if let err = error?.takeRetainedValue() {
                throw RSAError.encryptionFailed(err)
            }
            throw RSAError.keyCreationFailed(-1)
        }

        return secKey
    }
}
