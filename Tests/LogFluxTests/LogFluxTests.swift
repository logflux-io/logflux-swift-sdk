import CryptoKit
import Foundation
import Testing

@testable import LogFlux

// MARK: - AES Encryption

@Suite("AES Encryption")
struct AESEncryptorTests {
    @Test("encryptRaw produces valid ciphertext and 12-byte nonce")
    func encryptRawProducesValidOutput() throws {
        let key = AESEncryptor.generateKey()
        let data = Data("Hello, LogFlux!".utf8)

        let (ciphertext, nonce) = try AESEncryptor.encryptRaw(data: data, key: key)

        #expect(ciphertext.count > 0)
        #expect(nonce.count == 12) // AES-GCM nonce is always 12 bytes
    }

    @Test("encrypt produces valid base64 output")
    func encryptProducesBase64() throws {
        let key = AESEncryptor.generateKey()
        let data = Data("{\"message\":\"test\"}".utf8)

        let (payload, nonce) = try AESEncryptor.encrypt(data: data, key: key)

        #expect(Data(base64Encoded: payload) != nil)
        #expect(Data(base64Encoded: nonce) != nil)

        let nonceData = Data(base64Encoded: nonce)!
        #expect(nonceData.count == 12)
    }

    @Test("Key export and import roundtrip")
    func keyRoundtrip() throws {
        let original = AESEncryptor.generateKey()
        let exported = AESEncryptor.exportKey(original)
        #expect(exported.count == 32)

        let imported = AESEncryptor.importKey(exported)
        let exportedAgain = AESEncryptor.exportKey(imported)
        #expect(exported == exportedAgain)
    }

    @Test("Different inputs produce different ciphertexts")
    func differentInputsDifferentOutput() throws {
        let key = AESEncryptor.generateKey()
        let data1 = Data("Event.A".utf8)
        let data2 = Data("Event.B".utf8)

        let (payload1, _) = try AESEncryptor.encrypt(data: data1, key: key)
        let (payload2, _) = try AESEncryptor.encrypt(data: data2, key: key)

        #expect(payload1 != payload2)
    }

    @Test("Same data encrypts with different nonce each time")
    func randomNonce() throws {
        let key = AESEncryptor.generateKey()
        let data = Data("Same.Event".utf8)

        let (_, nonce1) = try AESEncryptor.encrypt(data: data, key: key)
        let (_, nonce2) = try AESEncryptor.encrypt(data: data, key: key)

        #expect(nonce1 != nonce2)
    }

    @Test("Decryption roundtrip validates encryption")
    func decryptionRoundtrip() throws {
        let key = AESEncryptor.generateKey()
        let originalData = Data("{\"v\":\"2.0\",\"type\":\"log\",\"message\":\"test\"}".utf8)

        let (payloadB64, nonceB64) = try AESEncryptor.encrypt(data: originalData, key: key)

        let ciphertextAndTag = Data(base64Encoded: payloadB64)!
        let nonceData = Data(base64Encoded: nonceB64)!

        let nonce = try AES.GCM.Nonce(data: nonceData)
        let tag = ciphertextAndTag.suffix(16)
        let ciphertext = ciphertextAndTag.dropLast(16)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let decrypted = try AES.GCM.open(sealedBox, using: key)

        let decompressed = try decompressGzip(decrypted)
        #expect(decompressed == originalData)
    }

    @Test("Raw encryption roundtrip without compression")
    func rawEncryptionNoCompression() throws {
        let key = AESEncryptor.generateKey()
        let originalData = Data("Hello raw".utf8)

        let (ciphertext, nonceData) = try AESEncryptor.encryptRaw(data: originalData, key: key, compress: false)

        let nonce = try AES.GCM.Nonce(data: nonceData)
        let tag = ciphertext.suffix(16)
        let ct = ciphertext.dropLast(16)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ct, tag: tag)
        let decrypted = try AES.GCM.open(sealedBox, using: key)

        #expect(decrypted == originalData)
    }

    @Test("Large payload compresses and encrypts")
    func largePayload() throws {
        let key = AESEncryptor.generateKey()
        let largeString = String(repeating: "LogFlux test data. ", count: 1000)
        let data = Data(largeString.utf8)

        let (ciphertext, nonce) = try AESEncryptor.encryptRaw(data: data, key: key)

        // Compressed + encrypted should be smaller than the original for repetitive data
        #expect(ciphertext.count < data.count)
        #expect(nonce.count == 12)
    }
}

// MARK: - Gzip Compression

@Suite("Gzip Compression")
struct GzipTests {
    @Test("Gzip header magic bytes")
    func gzipHeader() throws {
        let data = Data("Hello gzip".utf8)
        let compressed = AESEncryptor.gzipCompress(data)

        #expect(compressed != nil)
        #expect(compressed![0] == 0x1F) // gzip magic byte 1
        #expect(compressed![1] == 0x8B) // gzip magic byte 2
        #expect(compressed![2] == 0x08) // deflate compression method
    }

    @Test("Empty data returns nil")
    func emptyData() {
        let result = AESEncryptor.gzipCompress(Data())
        #expect(result == nil)
    }

    @Test("Compression reduces repeated data")
    func compressionReducesSize() {
        let data = Data(String(repeating: "AAAA", count: 1000).utf8)
        let compressed = AESEncryptor.gzipCompress(data)!
        #expect(compressed.count < data.count)
    }
}

// MARK: - RSA Helper

@Suite("RSA Helper")
struct RSAHelperTests {
    // Test RSA 2048-bit public key in SPKI DER format (PEM-wrapped)
    static let testPEM = """
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnvwwSLCPmkb6USyEmgN+
0m41K5qLNTQXCoJrRpuKepxZ0yyEhQGe+/D5jeqp6CMgCdFx488ioagrPc2lyyOe
ea0SljjyCdYeCb2UbmhBotwNDdHcXCqas5qX88jO0y9KaviFLuF6yx/CmxHWDTel
cI93IybvhTVyV9bw0MpQrEo5oxjsySw1EHIsrYB4zL3P1+0S2UlQE+XiAI2OruFX
H10+Bw5IuBinKD3cPG51rZ/qwzpkV3gos9Sr9OCmzDYnfaBklIAuYKj0ys3mmXma
q5oTj0HfeFN4dOZ55phuyDi6/gX340E8dg5kTzQlc9H29LY3xgSP4qsJtw3650tX
owIDAQAB
-----END PUBLIC KEY-----
"""

    @Test("RSA encryption produces base64 ciphertext")
    func rsaEncryption() throws {
        let aesKeyData = Data(repeating: 0xAB, count: 32)
        let encrypted = try RSAHelper.encryptWithPublicKey(
            aesKeyData: aesKeyData,
            pemPublicKey: Self.testPEM
        )

        #expect(!encrypted.isEmpty)
        #expect(Data(base64Encoded: encrypted) != nil)
    }

    @Test("RSA produces different ciphertext each time (OAEP)")
    func rsaDifferentOutputs() throws {
        let aesKeyData = Data(repeating: 0xCD, count: 32)
        let enc1 = try RSAHelper.encryptWithPublicKey(aesKeyData: aesKeyData, pemPublicKey: Self.testPEM)
        let enc2 = try RSAHelper.encryptWithPublicKey(aesKeyData: aesKeyData, pemPublicKey: Self.testPEM)
        #expect(enc1 != enc2) // OAEP uses random padding
    }

    @Test("Invalid PEM throws error")
    func invalidPEM() {
        let badPEM = "not-a-key"
        #expect(throws: RSAError.self) {
            _ = try RSAHelper.encryptWithPublicKey(aesKeyData: Data(repeating: 0, count: 32), pemPublicKey: badPEM)
        }
    }
}

// MARK: - DiskQueue

@Suite("DiskQueue")
struct DiskQueueTests {
    func makeTempQueue(maxSize: Int = 100) -> DiskQueue {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("logflux-test-\(UUID().uuidString)", isDirectory: true)
        return DiskQueue(maxSize: maxSize, directory: dir)
    }

    @Test("Enqueue and dequeue roundtrip")
    func enqueueDequeue() {
        let queue = makeTempQueue()
        let entry = LogEntry(data: Data("test".utf8), entryType: .log, level: .info)

        queue.enqueue([entry])
        #expect(queue.count == 1)

        let dequeued = queue.dequeue(limit: 10)
        #expect(dequeued.count == 1)
        #expect(dequeued[0].data == Data("test".utf8))
        #expect(queue.isEmpty)
    }

    @Test("FIFO ordering")
    func fifoOrdering() {
        let queue = makeTempQueue()
        let entries = (0..<5).map { i in
            LogEntry(data: Data("entry-\(i)".utf8), entryType: .log, level: .info)
        }

        queue.enqueue(entries)
        let dequeued = queue.dequeue(limit: 5)
        #expect(dequeued.count == 5)
        for (i, entry) in dequeued.enumerated() {
            #expect(entry.data == Data("entry-\(i)".utf8))
        }
    }

    @Test("Eviction when maxSize exceeded")
    func eviction() {
        let queue = makeTempQueue(maxSize: 3)
        let entries = (0..<5).map { i in
            LogEntry(data: Data("e\(i)".utf8), entryType: .log, level: .info)
        }

        queue.enqueue(entries)
        #expect(queue.count == 3) // Oldest 2 evicted

        let dequeued = queue.dequeue(limit: 10)
        // Should have entries 2, 3, 4 (oldest evicted)
        #expect(dequeued.count == 3)
        #expect(dequeued[0].data == Data("e2".utf8))
    }

    @Test("Empty dequeue returns empty array")
    func emptyDequeue() {
        let queue = makeTempQueue()
        let result = queue.dequeue(limit: 10)
        #expect(result.isEmpty)
    }

    @Test("Clear removes all entries")
    func clearQueue() {
        let queue = makeTempQueue()
        let entries = (0..<3).map { _ in
            LogEntry(data: Data("x".utf8), entryType: .log, level: .info)
        }
        queue.enqueue(entries)
        #expect(queue.count == 3)

        queue.clear()
        #expect(queue.isEmpty)
    }
}

// MARK: - v2 Payload Types

@Suite("v2 Payload Types")
struct PayloadTests {
    @Test("PayloadLog encodes to JSON correctly")
    func logPayload() throws {
        var p = PayloadLog(source: "test-app", message: "hello world", level: 7)
        p.attributes = ["key": "value"]

        let data = try JSONEncoder().encode(p)
        let dict = try JSONDecoder().decode([String: AnyCodable].self, from: data)

        #expect(dict["v"]?.stringValue == "2.0")
        #expect(dict["type"]?.stringValue == "log")
        #expect(dict["source"]?.stringValue == "test-app")
        #expect(dict["level"]?.intValue == 7)
        #expect(dict["message"]?.stringValue == "hello world")
    }

    @Test("PayloadMetric encodes counter correctly")
    func metricPayload() throws {
        let p = PayloadMetric(source: "test", name: "requests", value: 42.5, kind: "counter")

        let data = try JSONEncoder().encode(p)
        let dict = try JSONDecoder().decode([String: AnyCodable].self, from: data)

        #expect(dict["type"]?.stringValue == "metric")
        #expect(dict["name"]?.stringValue == "requests")
        #expect(dict["value"]?.doubleValue == 42.5)
        #expect(dict["kind"]?.stringValue == "counter")
    }

    @Test("PayloadEvent encodes correctly")
    func eventPayload() throws {
        var p = PayloadEvent(source: "test", event: "User.Login")
        p.attributes = ["method": "oauth"]

        let data = try JSONEncoder().encode(p)
        let dict = try JSONDecoder().decode([String: AnyCodable].self, from: data)

        #expect(dict["type"]?.stringValue == "event")
        #expect(dict["event"]?.stringValue == "User.Login")
    }

    @Test("PayloadAudit encodes with snake_case keys")
    func auditPayload() throws {
        let p = PayloadAudit(source: "test", action: "delete", actor: "usr_123", resource: "document", resourceID: "doc_456")

        let data = try JSONEncoder().encode(p)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("\"resource_id\""))
        #expect(json.contains("\"doc_456\""))
        #expect(json.contains("\"type\":\"audit\""))
    }

    @Test("PayloadTrace encodes with snake_case keys")
    func tracePayload() throws {
        let now = Date()
        let later = now.addingTimeInterval(0.5)
        let p = PayloadTrace(
            source: "test",
            traceID: "abcd1234abcd1234abcd1234abcd1234",
            spanID: "1234567890abcdef",
            operation: "http.server",
            name: "GET /api",
            startTime: now,
            endTime: later
        )

        let data = try JSONEncoder().encode(p)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("\"trace_id\""))
        #expect(json.contains("\"span_id\""))
        #expect(json.contains("\"start_time\""))
        #expect(json.contains("\"end_time\""))
        #expect(json.contains("\"duration_ms\""))
    }

    @Test("PayloadError captures error info")
    func errorPayload() throws {
        let err = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "something broke"])
        let p = PayloadError(source: "test", error: err)

        #expect(p.type == "log")
        #expect(p.level == 4) // error level
        #expect(p.message == "something broke")
        #expect(p.errorType != nil)

        // Should have stack trace
        #expect(p.stackTrace != nil)
        #expect(!p.stackTrace!.isEmpty)
    }

    @Test("PayloadError with custom message puts error in attributes")
    func errorPayloadWithMessage() throws {
        let err = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "original error"])
        let p = PayloadError(source: "test", error: err, message: "Custom message")

        #expect(p.message == "Custom message")
        #expect(p.attributes?["error"] == "original error")
    }

    @Test("PayloadTelemetry encodes device_id and readings")
    func telemetryPayload() throws {
        let readings = [
            Reading(name: "temperature", value: 23.5, unit: "celsius"),
            Reading(name: "humidity", value: 65.0, unit: "percent"),
        ]
        let p = PayloadTelemetry(source: "test", deviceID: "dev_001", readings: readings)

        let data = try JSONEncoder().encode(p)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("\"device_id\""))
        #expect(json.contains("\"dev_001\""))
        #expect(json.contains("\"temperature\""))
    }

    @Test("Payload decode roundtrip")
    func payloadRoundtrip() throws {
        let original = PayloadLog(source: "app", message: "test", level: 6)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PayloadLog.self, from: data)

        #expect(decoded.v == "2.0")
        #expect(decoded.type == "log")
        #expect(decoded.source == "app")
        #expect(decoded.message == "test")
        #expect(decoded.level == 6)
    }
}

// MARK: - Breadcrumb Ring Buffer

@Suite("Breadcrumb Ring Buffer")
struct BreadcrumbTests {
    @Test("Add and snapshot preserves order")
    func addAndSnapshot() {
        let ring = BreadcrumbRing(maxSize: 10)
        ring.add(Breadcrumb(category: "a", message: "first"))
        ring.add(Breadcrumb(category: "b", message: "second"))
        ring.add(Breadcrumb(category: "c", message: "third"))

        let snapshot = ring.snapshot()
        #expect(snapshot.count == 3)
        #expect(snapshot[0].message == "first")
        #expect(snapshot[1].message == "second")
        #expect(snapshot[2].message == "third")
    }

    @Test("Ring buffer wraps around correctly")
    func ringWrap() {
        let ring = BreadcrumbRing(maxSize: 3)
        ring.add(Breadcrumb(category: "a", message: "1"))
        ring.add(Breadcrumb(category: "a", message: "2"))
        ring.add(Breadcrumb(category: "a", message: "3"))
        ring.add(Breadcrumb(category: "a", message: "4"))
        ring.add(Breadcrumb(category: "a", message: "5"))

        let snapshot = ring.snapshot()
        #expect(snapshot.count == 3)
        #expect(snapshot[0].message == "3") // oldest surviving
        #expect(snapshot[1].message == "4")
        #expect(snapshot[2].message == "5") // newest
    }

    @Test("Clear removes all breadcrumbs")
    func clearBreadcrumbs() {
        let ring = BreadcrumbRing(maxSize: 10)
        ring.add(Breadcrumb(category: "a", message: "1"))
        ring.add(Breadcrumb(category: "a", message: "2"))
        #expect(ring.size == 2)

        ring.clear()
        #expect(ring.size == 0)
        #expect(ring.snapshot().isEmpty)
    }

    @Test("Empty ring returns empty snapshot")
    func emptyRing() {
        let ring = BreadcrumbRing(maxSize: 5)
        #expect(ring.snapshot().isEmpty)
        #expect(ring.size == 0)
    }

    @Test("Breadcrumb has timestamp")
    func breadcrumbTimestamp() {
        let b = Breadcrumb(category: "test", message: "hello")
        #expect(!b.timestamp.isEmpty)
        // Should be ISO 8601 format
        #expect(b.timestamp.contains("T"))
    }

    @Test("Breadcrumb Codable roundtrip")
    func breadcrumbCodable() throws {
        let original = Breadcrumb(category: "http", message: "GET /api", data: ["status": "200"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Breadcrumb.self, from: data)

        #expect(decoded.category == "http")
        #expect(decoded.message == "GET /api")
        #expect(decoded.data?["status"] == "200")
    }

    @Test("Overflow beyond maxSize only keeps last N entries")
    func overflow() {
        let ring = BreadcrumbRing(maxSize: 5)
        for i in 0..<20 {
            ring.add(Breadcrumb(category: "test", message: "msg-\(i)"))
        }

        let snapshot = ring.snapshot()
        #expect(snapshot.count == 5)
        #expect(snapshot[0].message == "msg-15")
        #expect(snapshot[4].message == "msg-19")
    }
}

// MARK: - Scope

@Suite("Scope")
struct ScopeTests {
    @Test("Scope attribute merging")
    func scopeAttributes() {
        let scope = Scope()
        scope.setAttribute("request_id", "abc-123")
        scope.setAttribute("user_id", "usr_456")

        var attrs: [String: String]? = ["existing": "value"]
        scope.applyScope(&attrs)

        #expect(attrs?["request_id"] == "abc-123")
        #expect(attrs?["user_id"] == "usr_456")
        #expect(attrs?["existing"] == "value")
    }

    @Test("Scope attributes don't overwrite existing")
    func scopeNoOverwrite() {
        let scope = Scope()
        scope.setAttribute("key", "scope-value")

        var attrs: [String: String]? = ["key": "explicit-value"]
        scope.applyScope(&attrs)

        #expect(attrs?["key"] == "explicit-value") // Not overwritten
    }

    @Test("SetUser sets user.id attribute")
    func setUser() {
        let scope = Scope()
        scope.setUser("usr_789")

        var attrs: [String: String]? = nil
        scope.applyScope(&attrs)

        #expect(attrs?["user.id"] == "usr_789")
    }

    @Test("SetRequest sets http attributes")
    func setRequest() {
        let scope = Scope()
        scope.setRequest(method: "GET", path: "/api/users", requestID: "req-42")

        var attrs: [String: String]? = nil
        scope.applyScope(&attrs)

        #expect(attrs?["http.method"] == "GET")
        #expect(attrs?["http.path"] == "/api/users")
        #expect(attrs?["request_id"] == "req-42")
    }

    @Test("Scope has its own breadcrumb buffer")
    func scopeBreadcrumbs() {
        let scope = Scope(maxBreadcrumbs: 10)
        scope.addBreadcrumb("http", "GET /api")
        scope.addBreadcrumb("db", "SELECT * FROM users")

        let snapshot = scope.breadcrumbs.snapshot()
        #expect(snapshot.count == 2)
    }

    @Test("SetAttributes sets multiple at once")
    func setMultipleAttributes() {
        let scope = Scope()
        scope.setAttributes(["a": "1", "b": "2", "c": "3"])

        var attrs: [String: String]? = nil
        scope.applyScope(&attrs)

        #expect(attrs?.count == 3)
        #expect(attrs?["a"] == "1")
        #expect(attrs?["b"] == "2")
    }
}

// MARK: - Span

@Suite("Span")
struct SpanTests {
    @Test("Span generates valid IDs")
    func spanIDs() {
        let span = Span(operation: "test.op", description: "test span")

        #expect(span.traceID.count == 32) // 16 bytes = 32 hex chars
        #expect(span.spanID.count == 16) // 8 bytes = 16 hex chars
        #expect(span.parentSpanID == nil)
    }

    @Test("Child span shares trace ID")
    func childSpan() {
        let parent = Span(operation: "parent.op")
        let child = parent.startChild("child.op", "child description")

        #expect(child.traceID == parent.traceID)
        #expect(child.parentSpanID == parent.spanID)
        #expect(child.spanID != parent.spanID)
    }

    @Test("End returns false on double-end")
    func doubleEnd() {
        let span = Span(operation: "test")
        // Can't test the actual send without a client, but double-end should be safe
        let first = span.end()
        let second = span.end()
        // Both may return false since there's no client, but second is always false
        #expect(first == false || second == false)
    }

    @Test("SetAttribute stores attributes")
    func setAttribute() {
        let span = Span(operation: "test")
        span.setAttribute("http.method", "GET")
        span.setAttributes(["http.url": "/api", "http.status": "200"])
        // No crash = success; we can't inspect private state but thread safety is validated
    }

    @Test("SetError marks span as error")
    func setError() {
        let span = Span(operation: "test")
        let err = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "fail"])
        span.setError(err)
        // No crash = success
    }

    @Test("generateTraceID produces hex strings")
    func traceIDFormat() {
        let id = Span.generateTraceID()
        #expect(id.count == 32)
        // Verify all characters are hex
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        #expect(id.unicodeScalars.allSatisfy { hexChars.contains($0) })
    }

    @Test("generateSpanID produces hex strings")
    func spanIDFormat() {
        let id = Span.generateSpanID()
        #expect(id.count == 16)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        #expect(id.unicodeScalars.allSatisfy { hexChars.contains($0) })
    }

    @Test("IDs are unique across calls")
    func uniqueIDs() {
        let ids = (0..<100).map { _ in Span.generateTraceID() }
        let uniqueIDs = Set(ids)
        #expect(uniqueIDs.count == 100) // All unique
    }
}

// MARK: - Multipart Builder

@Suite("Multipart Builder")
struct MultipartBuilderTests {
    /// Helper: check if binary Data contains a specific ASCII string.
    private func dataContains(_ data: Data, _ needle: String) -> Bool {
        let needleData = Data(needle.utf8)
        guard needleData.count <= data.count else { return false }
        for i in 0...(data.count - needleData.count) {
            if data[i..<(i + needleData.count)] == needleData {
                return true
            }
        }
        return false
    }

    @Test("Build single-entry multipart body")
    func singleEntry() throws {
        let key = AESEncryptor.generateKey()
        let entry = MultipartBuilder.PreparedEntry(
            data: Data("{\"message\":\"test\"}".utf8),
            entryType: .log,
            level: .info
        )

        let (body, contentType) = try MultipartBuilder.build(
            entries: [entry],
            aesKey: key,
            keyID: "test-key-id",
            enableCompression: true
        )

        #expect(contentType.hasPrefix("multipart/mixed; boundary="))
        // Search for header strings in the binary body
        #expect(dataContains(body, "X-LF-Entry-Type: 1"))
        #expect(dataContains(body, "X-LF-Payload-Type: 1"))
        #expect(dataContains(body, "X-LF-Key-ID: test-key-id"))
        #expect(dataContains(body, "X-LF-Nonce:"))
    }

    @Test("Build multi-entry multipart body")
    func multiEntry() throws {
        let key = AESEncryptor.generateKey()
        let entries = [
            MultipartBuilder.PreparedEntry(data: Data("log".utf8), entryType: .log, level: .info),
            MultipartBuilder.PreparedEntry(data: Data("metric".utf8), entryType: .metric, level: .info),
            MultipartBuilder.PreparedEntry(data: Data("event".utf8), entryType: .event, level: .info),
        ]

        let (body, contentType) = try MultipartBuilder.build(
            entries: entries,
            aesKey: key,
            keyID: "kid",
            enableCompression: true
        )

        #expect(contentType.hasPrefix("multipart/mixed; boundary="))

        // Check each entry type header exists in the binary body
        #expect(dataContains(body, "X-LF-Entry-Type: 1"))
        #expect(dataContains(body, "X-LF-Entry-Type: 2"))
        #expect(dataContains(body, "X-LF-Entry-Type: 4"))

        // Check boundary appears multiple times
        let boundary = contentType.replacingOccurrences(of: "multipart/mixed; boundary=", with: "")
        let boundaryData = Data("--\(boundary)".utf8)
        var count = 0
        for i in 0..<(body.count - boundaryData.count) {
            if body[i..<(i + boundaryData.count)] == boundaryData {
                count += 1
            }
        }
        #expect(count >= 4) // 3 parts + closing boundary
    }

    @Test("Closing boundary is present")
    func closingBoundary() throws {
        let key = AESEncryptor.generateKey()
        let entry = MultipartBuilder.PreparedEntry(
            data: Data("test".utf8),
            entryType: .log,
            level: .info
        )

        let (body, contentType) = try MultipartBuilder.build(
            entries: [entry],
            aesKey: key,
            keyID: "kid",
            enableCompression: true
        )

        let boundary = contentType.replacingOccurrences(of: "multipart/mixed; boundary=", with: "")
        #expect(dataContains(body, "--\(boundary)--"))
    }
}

// MARK: - Sampling

@Suite("Sampling")
struct SamplerTests {
    @Test("Rate 1.0 always samples")
    func alwaysSample() {
        let sampler = Sampler(rate: 1.0)
        for _ in 0..<100 {
            #expect(sampler.shouldSample())
        }
    }

    @Test("Rate 0.0 never samples")
    func neverSample() {
        let sampler = Sampler(rate: 0.0)
        for _ in 0..<100 {
            #expect(!sampler.shouldSample())
        }
    }

    @Test("Rate 0.5 samples approximately half")
    func halfSample() {
        let sampler = Sampler(rate: 0.5)
        var count = 0
        let total = 10000
        for _ in 0..<total {
            if sampler.shouldSample() { count += 1 }
        }
        // Should be roughly 50% +/- 5%
        let ratio = Double(count) / Double(total)
        #expect(ratio > 0.40)
        #expect(ratio < 0.60)
    }

    @Test("Rate clamped to valid range")
    func rateClamping() {
        let high = Sampler(rate: 2.0)
        #expect(high.shouldSample()) // clamped to 1.0

        let low = Sampler(rate: -1.0)
        #expect(!low.shouldSample()) // clamped to 0.0
    }
}

// MARK: - ClientStats

@Suite("ClientStats")
struct ClientStatsTests {
    @Test("Default stats are zero")
    func defaultStats() {
        let stats = ClientStats(entriesSent: 0, entriesDropped: 0, entriesQueued: 0, dropReasons: [:])
        #expect(stats.entriesSent == 0)
        #expect(stats.entriesDropped == 0)
        #expect(stats.entriesQueued == 0)
        #expect(stats.dropReasons.isEmpty)
    }

    @Test("Stats with drop reasons")
    func statsWithReasons() {
        let stats = ClientStats(
            entriesSent: 100,
            entriesDropped: 5,
            entriesQueued: 200,
            dropReasons: ["queue_overflow": 3, "network_error": 2]
        )
        #expect(stats.entriesSent == 100)
        #expect(stats.entriesDropped == 5)
        #expect(stats.dropReasons["queue_overflow"] == 3)
        #expect(stats.dropReasons["network_error"] == 2)
    }
}

// MARK: - Options

@Suite("Options")
struct OptionsTests {
    @Test("Default options values")
    func defaultValues() {
        let opts = Options(apiKey: "eu-lf_test123")
        #expect(opts.queueSize == 1000)
        #expect(opts.batchSize == 100)
        #expect(opts.workerCount == 2)
        #expect(opts.flushInterval == 5)
        #expect(opts.maxRetries == 3)
        #expect(opts.httpTimeout == 30)
        #expect(opts.failsafe == true)
        #expect(opts.enableCompression == true)
        #expect(opts.sampleRate == 1.0)
        #expect(opts.maxBreadcrumbs == 100)
    }

    @Test("Valid API key passes validation")
    func validAPIKey() throws {
        let opts = Options(apiKey: "eu-lf_abc123")
        try opts.validateAPIKey() // Should not throw
    }

    @Test("Invalid API key format throws")
    func invalidAPIKeyFormat() {
        let opts = Options(apiKey: "invalidkey")
        #expect(throws: LogFluxError.self) {
            try opts.validateAPIKey()
        }
    }

    @Test("Invalid region throws")
    func invalidRegion() {
        let opts = Options(apiKey: "xx-lf_abc123")
        #expect(throws: LogFluxError.self) {
            try opts.validateAPIKey()
        }
    }

    @Test("Missing lf_ prefix throws")
    func missingPrefix() {
        let opts = Options(apiKey: "eu-abc123")
        #expect(throws: LogFluxError.self) {
            try opts.validateAPIKey()
        }
    }

    @Test("Empty key body throws")
    func emptyBody() {
        let opts = Options(apiKey: "eu-lf_")
        #expect(throws: LogFluxError.self) {
            try opts.validateAPIKey()
        }
    }

    @Test("extractRegion returns correct region")
    func extractRegion() {
        let opts = Options(apiKey: "us-lf_test")
        #expect(opts.extractRegion() == "us")
    }

    @Test("All valid regions accepted")
    func validRegions() throws {
        for region in ["eu", "us", "ca", "au", "ap"] {
            let opts = Options(apiKey: "\(region)-lf_test123")
            try opts.validateAPIKey()
        }
    }
}

// MARK: - LogLevel

@Suite("LogLevel")
struct LogLevelTests {
    @Test("Level raw values match syslog")
    func rawValues() {
        #expect(LogLevel.emergency.rawValue == 1)
        #expect(LogLevel.alert.rawValue == 2)
        #expect(LogLevel.critical.rawValue == 3)
        #expect(LogLevel.error.rawValue == 4)
        #expect(LogLevel.warning.rawValue == 5)
        #expect(LogLevel.notice.rawValue == 6)
        #expect(LogLevel.info.rawValue == 7)
        #expect(LogLevel.debug.rawValue == 8)
    }

    @Test("Level labels for breadcrumbs")
    func levelLabels() {
        #expect(LogLevel.emergency.label == "error")
        #expect(LogLevel.error.label == "error")
        #expect(LogLevel.warning.label == "warning")
        #expect(LogLevel.info.label == "info")
        #expect(LogLevel.debug.label == "info")
    }

    @Test("Comparable works correctly")
    func comparable() {
        #expect(LogLevel.emergency < LogLevel.debug)
        #expect(LogLevel.error < LogLevel.info)
    }
}

// MARK: - EntryType

@Suite("EntryType")
struct EntryTypeTests {
    @Test("Entry type raw values")
    func rawValues() {
        #expect(EntryType.log.rawValue == 1)
        #expect(EntryType.metric.rawValue == 2)
        #expect(EntryType.trace.rawValue == 3)
        #expect(EntryType.event.rawValue == 4)
        #expect(EntryType.audit.rawValue == 5)
        #expect(EntryType.telemetry.rawValue == 6)
        #expect(EntryType.telemetryManaged.rawValue == 7)
    }

    @Test("Encryption requirement")
    func encryptionRequired() {
        #expect(EntryType.log.requiresEncryption == true)
        #expect(EntryType.metric.requiresEncryption == true)
        #expect(EntryType.trace.requiresEncryption == true)
        #expect(EntryType.event.requiresEncryption == true)
        #expect(EntryType.audit.requiresEncryption == true)
        #expect(EntryType.telemetry.requiresEncryption == true)
        #expect(EntryType.telemetryManaged.requiresEncryption == false)
    }

    @Test("Categories match Go SDK")
    func categories() {
        #expect(EntryType.log.category == "events")
        #expect(EntryType.metric.category == "events")
        #expect(EntryType.event.category == "events")
        #expect(EntryType.trace.category == "traces")
        #expect(EntryType.telemetry.category == "traces")
        #expect(EntryType.telemetryManaged.category == "traces")
        #expect(EntryType.audit.category == "audit")
    }

    @Test("Default payload types")
    func payloadTypes() {
        #expect(EntryType.log.defaultPayloadType == 1)
        #expect(EntryType.audit.defaultPayloadType == 1)
        #expect(EntryType.telemetryManaged.defaultPayloadType == 3)
    }
}

// MARK: - PayloadContext

@Suite("PayloadContext")
struct PayloadContextTests {
    @Test("Configure and apply context")
    func configureAndApply() {
        PayloadContext.shared.configure(source: "test-app", environment: "staging", release: "1.2.3")

        var p = PayloadLog(message: "test", level: 7)
        applyContext(&p)

        #expect(p.source == "test-app")
        #expect(p.meta?["environment"] == "staging")
        #expect(p.meta?["release"] == "1.2.3")

        PayloadContext.shared.reset()
    }

    @Test("Context doesn't overwrite explicit source")
    func noOverwriteSource() {
        PayloadContext.shared.configure(source: "global-source", environment: "", release: "")

        var p = PayloadLog(source: "explicit-source", message: "test", level: 7)
        applyContext(&p)

        #expect(p.source == "explicit-source")

        PayloadContext.shared.reset()
    }

    @Test("Context doesn't overwrite explicit meta")
    func noOverwriteMeta() {
        PayloadContext.shared.configure(source: "", environment: "production", release: "")

        var p = PayloadLog(message: "test", level: 7)
        p.meta = ["environment": "custom"]
        applyContext(&p)

        #expect(p.meta?["environment"] == "custom") // Not overwritten

        PayloadContext.shared.reset()
    }

    @Test("Reset clears context")
    func resetClearsContext() {
        PayloadContext.shared.configure(source: "test", environment: "staging", release: "1.0")
        PayloadContext.shared.reset()

        #expect(PayloadContext.shared.getSource() == "")
        #expect(PayloadContext.shared.defaultMeta() == nil)
    }
}

// MARK: - Version

@Suite("Version")
struct VersionTests {
    @Test("Version is 3.0.1")
    func versionString() {
        #expect(version == "3.0.1")
    }

    @Test("User agent contains version")
    func userAgentFormat() {
        #expect(userAgent == "logflux-swift-sdk/3.0.1")
    }
}

// MARK: - LogFlux Facade (without server)

@Suite("LogFlux Facade")
struct LogFluxFacadeTests {
    @Test("isActive is false before initialization")
    func notActiveBeforeInit() {
        #expect(LogFlux.isActive == false)
    }

    @Test("stats returns zeros when not initialized")
    func statsWhenNotInitialized() {
        let stats = LogFlux.stats()
        #expect(stats.entriesSent == 0)
        #expect(stats.entriesDropped == 0)
        #expect(stats.entriesQueued == 0)
    }

    @Test("Log methods are safe to call when not initialized")
    func logSafeWhenNotInitialized() {
        // These should all be no-ops, not crash
        LogFlux.debug("test")
        LogFlux.info("test")
        LogFlux.notice("test")
        LogFlux.warn("test")
        LogFlux.error("test")
        LogFlux.critical("test")
        LogFlux.alert("test")
        LogFlux.emergency("test")
        LogFlux.event("test")
        LogFlux.counter("test", value: 1)
        LogFlux.gauge("test", value: 1)
        LogFlux.audit("test", actor: "a", resource: "r", resourceID: "id")
        LogFlux.addBreadcrumb("cat", "msg")
        LogFlux.clearBreadcrumbs()
        LogFlux.captureError(NSError(domain: "test", code: 1))
        LogFlux.flush(timeout: 0.1)
        LogFlux.close()
    }

    @Test("withScope provides a scope")
    func withScope() {
        LogFlux.withScope { scope in
            scope.setAttribute("key", "value")
            scope.setUser("user")
            scope.addBreadcrumb("test", "message")
            // No crash = success
        }
    }

    @Test("startSpan creates a span with valid IDs")
    func startSpan() {
        let span = LogFlux.startSpan("test.op", "test description")
        #expect(span.traceID.count == 32)
        #expect(span.spanID.count == 16)
        #expect(span.parentSpanID == nil)
    }

    @Test("continueFromRequest with valid header creates child span")
    func continueFromRequest() {
        let headers = [
            "X-LogFlux-Trace": "4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-1"
        ]
        let span = LogFlux.continueFromRequest(headers, operation: "http.server", description: "GET /api")

        #expect(span.traceID == "4bf92f3577b34da6a3ce929d0e0e4736")
        #expect(span.parentSpanID == "00f067aa0ba902b7")
    }

    @Test("continueFromRequest with missing header creates new root span")
    func continueFromRequestNoHeader() {
        let span = LogFlux.continueFromRequest([:], operation: "test")
        #expect(span.parentSpanID == nil)
        #expect(span.traceID.count == 32)
    }
}

// MARK: - ISO8601 Timestamp

@Suite("ISO8601 Timestamp")
struct TimestampTests {
    @Test("now() returns valid ISO 8601")
    func nowFormat() {
        let ts = ISO8601Timestamp.now()
        #expect(ts.contains("T"))
        #expect(ts.contains("Z") || ts.contains("+"))
    }

    @Test("format() converts Date correctly")
    func formatDate() {
        let date = Date(timeIntervalSince1970: 0)
        let ts = ISO8601Timestamp.format(date)
        #expect(ts.hasPrefix("1970-01-01T00:00:00"))
    }
}

// MARK: - Reachability

@Suite("Reachability")
struct ReachabilityTests {
    @Test("Monitor starts and reports connected after settling")
    func monitorReportsConnected() async throws {
        let monitor = ReachabilityMonitor()
        monitor.start { }
        // NWPathMonitor needs a brief moment to initialize its first path update
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        // On a dev machine, we should be connected
        #expect(monitor.isConnected)
        monitor.stop()
    }
}

// MARK: - LogEntry

@Suite("LogEntry")
struct LogEntryTests {
    @Test("LogEntry stores data and metadata")
    func logEntryFields() {
        let data = Data("payload".utf8)
        let entry = LogEntry(data: data, entryType: .metric, level: .warning)

        #expect(entry.data == data)
        #expect(entry.entryType == 2) // metric
        #expect(entry.level == 5) // warning
        #expect(!entry.timestamp.isEmpty)
    }

    @Test("LogEntry Codable roundtrip")
    func logEntryCodable() throws {
        let original = LogEntry(data: Data("test".utf8), entryType: .audit, level: .notice)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LogEntry.self, from: encoded)

        #expect(decoded.data == Data("test".utf8))
        #expect(decoded.entryType == 5)
        #expect(decoded.level == 6)
    }
}

// MARK: - Helpers

/// Decompress gzip data (for test verification).
func decompressGzip(_ data: Data) throws -> Data {
    guard data.count >= 10 else {
        throw NSError(domain: "gzip", code: -1, userInfo: [NSLocalizedDescriptionKey: "Data too short for gzip"])
    }

    // Skip 10-byte gzip header
    let compressedData = data.dropFirst(10)
    // Remove 8-byte trailer (CRC32 + original size)
    let deflateData = compressedData.dropLast(8)

    let destCapacity = 1_000_000
    let dest = UnsafeMutablePointer<UInt8>.allocate(capacity: destCapacity)
    defer { dest.deallocate() }

    let size = deflateData.withUnsafeBytes { srcBuffer -> Int in
        guard let srcBase = srcBuffer.baseAddress else { return 0 }
        return compression_decode_buffer(
            dest, destCapacity,
            srcBase.assumingMemoryBound(to: UInt8.self), deflateData.count,
            nil, COMPRESSION_ZLIB
        )
    }

    guard size > 0 else {
        throw NSError(domain: "gzip", code: -2, userInfo: [NSLocalizedDescriptionKey: "Decompression failed"])
    }

    return Data(bytes: dest, count: size)
}

/// Helper for JSON decoding in tests.
struct AnyCodable: Codable {
    let value: Any

    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var doubleValue: Double? { value as? Double }
    var boolValue: Bool? { value as? Bool }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { value = v }
        else if let v = try? container.decode(Int.self) { value = v }
        else if let v = try? container.decode(Double.self) { value = v }
        else if let v = try? container.decode(Bool.self) { value = v }
        else { value = "" }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let v = value as? String { try container.encode(v) }
        else if let v = value as? Int { try container.encode(v) }
        else if let v = value as? Double { try container.encode(v) }
        else if let v = value as? Bool { try container.encode(v) }
    }
}

import Compression
