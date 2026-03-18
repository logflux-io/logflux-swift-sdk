import Compression
import CryptoKit
import Foundation

enum AESEncryptorError: Error {
    case compressionFailed
    case encryptionFailed(Error)
}

/// AES-256-GCM encryption with gzip compression, matching the logflux-agent protocol.
enum AESEncryptor {

    /// Encrypt raw data for multipart binary transport.
    /// Flow: optional gzip compress -> AES-256-GCM encrypt
    /// Returns raw ciphertext+tag and nonce (no base64).
    static func encryptRaw(
        data: Data,
        key: SymmetricKey,
        compress: Bool = true
    ) throws -> (ciphertext: Data, nonce: Data) {
        let plaintext: Data
        if compress {
            guard let compressed = gzipCompress(data) else {
                throw AESEncryptorError.compressionFailed
            }
            plaintext = compressed
        } else {
            plaintext = data
        }

        let nonce = AES.GCM.Nonce()

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        } catch {
            throw AESEncryptorError.encryptionFailed(error)
        }

        // ciphertext + tag (matching Go's cipher.AEAD.Seal() output)
        let ciphertextAndTag = sealedBox.ciphertext + sealedBox.tag
        let nonceData = nonce.withUnsafeBytes { Data($0) }

        return (ciphertextAndTag, nonceData)
    }

    /// Encrypt a v1 LogEntry for legacy base64 wire format (kept for tests).
    /// Flow: JSON encode -> gzip compress -> AES-256-GCM encrypt
    /// Returns (base64 payload, base64 nonce).
    static func encrypt(
        data: Data,
        key: SymmetricKey
    ) throws -> (payload: String, nonce: String) {
        let (ciphertext, nonceData) = try encryptRaw(data: data, key: key, compress: true)
        return (ciphertext.base64EncodedString(), nonceData.base64EncodedString())
    }

    /// Generate a new random 32-byte AES-256 key.
    static func generateKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    /// Export key bytes for RSA encryption and Keychain storage.
    static func exportKey(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    /// Import key from raw bytes.
    static func importKey(_ data: Data) -> SymmetricKey {
        SymmetricKey(data: data)
    }

    // MARK: - Gzip

    /// Gzip compress data. Uses Compression framework for raw deflate,
    /// then wraps in gzip container (RFC 1952).
    static func gzipCompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }

        // Raw deflate using Compression framework
        let destCapacity = max(data.count * 2, 1024)
        let dest = UnsafeMutablePointer<UInt8>.allocate(capacity: destCapacity)
        defer { dest.deallocate() }

        let compressedSize = data.withUnsafeBytes { srcBuffer -> Int in
            guard let srcBase = srcBuffer.baseAddress else { return 0 }
            return compression_encode_buffer(
                dest, destCapacity,
                srcBase.assumingMemoryBound(to: UInt8.self), data.count,
                nil, COMPRESSION_ZLIB
            )
        }

        guard compressedSize > 0 else { return nil }

        // Gzip container: header + deflated data + CRC32 + original size
        var gzip = Data(capacity: 10 + compressedSize + 8)

        // 10-byte gzip header (RFC 1952)
        gzip.append(contentsOf: [0x1f, 0x8b, 0x08, 0x00] as [UInt8]) // magic + deflate + no flags
        gzip.append(contentsOf: [0x00, 0x00, 0x00, 0x00] as [UInt8]) // mtime
        gzip.append(contentsOf: [0x00, 0x13] as [UInt8])             // xfl + OS (0x13 = macOS)

        // Compressed data
        gzip.append(Data(bytes: dest, count: compressedSize))

        // CRC32 of uncompressed data (little-endian)
        var crc = GzipCRC32.compute(data)
        gzip.append(Data(bytes: &crc, count: 4))

        // Original uncompressed size mod 2^32 (little-endian)
        var size = UInt32(truncatingIfNeeded: data.count)
        gzip.append(Data(bytes: &size, count: 4))

        return gzip
    }
}

// MARK: - CRC32 (IEEE / gzip)

/// Pure Swift CRC32 implementation for gzip footer.
enum GzipCRC32 {
    static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var crc = UInt32(i)
            for _ in 0..<8 {
                if crc & 1 == 1 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
            return crc
        }
    }()

    static func compute(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ table[index]
        }
        return crc ^ 0xFFFFFFFF
    }
}
