import CryptoKit
import Foundation

/// Builds multipart/mixed request bodies with binary ciphertext for the /v1/ingest endpoint.
enum MultipartBuilder {
    /// A prepared entry ready for multipart encoding.
    struct PreparedEntry {
        let data: Data
        let entryType: EntryType
        let level: LogLevel
    }

    /// Builds a multipart/mixed body from prepared entries.
    /// Each MIME part contains raw ciphertext with metadata in headers.
    static func build(
        entries: [PreparedEntry],
        aesKey: SymmetricKey,
        keyID: String,
        enableCompression: Bool
    ) throws -> (body: Data, contentType: String) {
        let boundary = "logflux-\(UUID().uuidString)"
        var body = Data()

        for entry in entries {
            let payloadType = entry.entryType.defaultPayloadType

            // Write boundary
            body.append(Data("--\(boundary)\r\n".utf8))

            // Write headers
            body.append(Data("Content-Type: application/octet-stream\r\n".utf8))
            body.append(Data("X-LF-Entry-Type: \(entry.entryType.rawValue)\r\n".utf8))
            body.append(Data("X-LF-Payload-Type: \(payloadType)\r\n".utf8))
            body.append(Data("X-LF-Timestamp: \(ISO8601Timestamp.now())\r\n".utf8))

            let partBody: Data

            if entry.entryType.requiresEncryption {
                // Encrypt: gzip + AES-256-GCM
                let (ciphertext, nonce) = try AESEncryptor.encryptRaw(
                    data: entry.data,
                    key: aesKey,
                    compress: enableCompression
                )
                body.append(Data("X-LF-Key-ID: \(keyID)\r\n".utf8))
                body.append(Data("X-LF-Nonce: \(nonce.base64EncodedString())\r\n".utf8))
                partBody = ciphertext
            } else {
                // Type 7: compress only (no encryption)
                if enableCompression, let compressed = AESEncryptor.gzipCompress(entry.data) {
                    partBody = compressed
                } else {
                    partBody = entry.data
                }
            }

            // Empty line separating headers from body
            body.append(Data("\r\n".utf8))
            // Part body
            body.append(partBody)
            body.append(Data("\r\n".utf8))
        }

        // Closing boundary
        body.append(Data("--\(boundary)--\r\n".utf8))

        return (body, "multipart/mixed; boundary=\(boundary)")
    }
}
