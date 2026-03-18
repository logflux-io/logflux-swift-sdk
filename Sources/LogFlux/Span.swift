import Foundation

/// Represents an in-flight trace span. Call `end()` to finish and send it.
///
/// Usage:
/// ```swift
/// let span = LogFlux.startSpan("http.server", "GET /api/users")
/// defer { span.end() }
/// span.setAttribute("http.method", "GET")
/// if error != nil { span.setError(error) }
/// ```
public final class Span: @unchecked Sendable {
    public let traceID: String
    public let spanID: String
    public let parentSpanID: String?

    private let operation: String
    private let description: String?
    private let startTime: Date
    private let lock = NSLock()
    private var status: String = "ok"
    private var attributes: [String: String] = [:]
    private var ended: Bool = false

    init(
        traceID: String? = nil,
        spanID: String? = nil,
        parentSpanID: String? = nil,
        operation: String,
        description: String? = nil
    ) {
        self.traceID = traceID ?? Self.generateTraceID()
        self.spanID = spanID ?? Self.generateSpanID()
        self.parentSpanID = parentSpanID
        self.operation = operation
        self.description = description
        self.startTime = Date()
    }

    /// Creates a child span under this span (same trace ID).
    public func startChild(_ operation: String, _ description: String? = nil) -> Span {
        Span(
            traceID: traceID,
            parentSpanID: spanID,
            operation: operation,
            description: description
        )
    }

    /// Finishes the span, computes duration, and sends it as a trace entry.
    @discardableResult
    public func end() -> Bool {
        lock.lock()
        if ended {
            lock.unlock()
            return false
        }
        ended = true
        let attrs = attributes
        let stat = status
        lock.unlock()

        let endTime = Date()

        guard let client = LogFlux._client else { return false }

        var p = PayloadTrace(
            traceID: traceID,
            spanID: spanID,
            parentSpanID: parentSpanID,
            operation: operation,
            name: description,
            startTime: startTime,
            endTime: endTime
        )
        p.status = stat
        applyContext(&p)
        if !attrs.isEmpty {
            p.attributes = attrs
        }

        guard let data = try? JSONEncoder().encode(p) else { return false }
        client.enqueue(data: data, entryType: .trace, level: .info)
        return true
    }

    // MARK: - Setters

    /// Sets a span attribute.
    public func setAttribute(_ key: String, _ value: String) {
        lock.lock()
        attributes[key] = value
        lock.unlock()
    }

    /// Sets multiple span attributes.
    public func setAttributes(_ attrs: [String: String]) {
        lock.lock()
        for (k, v) in attrs {
            attributes[k] = v
        }
        lock.unlock()
    }

    /// Sets the span status ("ok" or "error").
    public func setStatus(_ status: String) {
        lock.lock()
        self.status = status
        lock.unlock()
    }

    /// Marks the span as errored and records the error message.
    public func setError(_ error: Error) {
        lock.lock()
        status = "error"
        attributes["error.message"] = error.localizedDescription
        lock.unlock()
    }

    // MARK: - ID generation

    /// Generates a 32-char hex trace ID.
    static func generateTraceID() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Generates a 16-char hex span ID.
    static func generateSpanID() -> String {
        var bytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, 8, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
