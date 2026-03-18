import Foundation

/// Per-request context isolation. Attributes and breadcrumbs set on a scope
/// are merged into every entry sent through it, without affecting global state.
///
/// Usage:
/// ```swift
/// LogFlux.withScope { scope in
///     scope.setAttribute("request_id", "abc-123")
///     scope.setUser("usr_456")
///     scope.addBreadcrumb("http", "GET /api/users")
///     scope.info("processing request")
///     scope.captureError(error)
/// }
/// ```
public final class Scope: @unchecked Sendable {
    private let lock = NSLock()
    private var attributes: [String: String] = [:]
    let breadcrumbs: BreadcrumbRing

    init(maxBreadcrumbs: Int = 100) {
        self.breadcrumbs = BreadcrumbRing(maxSize: maxBreadcrumbs)
    }

    // MARK: - Attribute setters

    /// Sets a key-value pair that will be merged into every entry.
    public func setAttribute(_ key: String, _ value: String) {
        lock.lock()
        attributes[key] = value
        lock.unlock()
    }

    /// Sets multiple attributes at once.
    public func setAttributes(_ attrs: [String: String]) {
        lock.lock()
        for (k, v) in attrs {
            attributes[k] = v
        }
        lock.unlock()
    }

    /// Convenience for setting user context.
    public func setUser(_ userID: String) {
        setAttribute("user.id", userID)
    }

    /// Convenience for setting request context.
    public func setRequest(method: String, path: String, requestID: String? = nil) {
        lock.lock()
        attributes["http.method"] = method
        attributes["http.path"] = path
        if let rid = requestID, !rid.isEmpty {
            attributes["request_id"] = rid
        }
        lock.unlock()
    }

    /// Sets trace context on this scope.
    public func setTraceContext(traceID: String, spanID: String) {
        lock.lock()
        attributes["trace_id"] = traceID
        attributes["span_id"] = spanID
        lock.unlock()
    }

    // MARK: - Breadcrumbs

    /// Adds a breadcrumb to this scope's trail.
    public func addBreadcrumb(_ category: String, _ message: String, data: [String: String]? = nil) {
        breadcrumbs.add(Breadcrumb(category: category, message: message, data: data))
    }

    // MARK: - Log methods

    public func debug(_ message: String, attributes: [String: String]? = nil) {
        scopedLog(level: .debug, message: message, extraAttrs: attributes)
    }

    public func info(_ message: String, attributes: [String: String]? = nil) {
        scopedLog(level: .info, message: message, extraAttrs: attributes)
    }

    public func notice(_ message: String, attributes: [String: String]? = nil) {
        scopedLog(level: .notice, message: message, extraAttrs: attributes)
    }

    public func warn(_ message: String, attributes: [String: String]? = nil) {
        scopedLog(level: .warning, message: message, extraAttrs: attributes)
    }

    public func error(_ message: String, attributes: [String: String]? = nil) {
        scopedLog(level: .error, message: message, extraAttrs: attributes)
    }

    public func critical(_ message: String, attributes: [String: String]? = nil) {
        scopedLog(level: .critical, message: message, extraAttrs: attributes)
    }

    // MARK: - Event

    public func event(_ name: String, attributes: [String: String]? = nil) {
        guard let client = LogFlux._client else { return }
        var p = PayloadEvent(event: name)
        applyContext(&p)
        applyScope(&p.attributes)
        if let extraAttrs = attributes {
            if p.attributes == nil { p.attributes = [:] }
            for (k, v) in extraAttrs { p.attributes?[k] = v }
        }

        breadcrumbs.add(Breadcrumb(category: "event", message: name, data: attributes))

        guard let data = try? JSONEncoder().encode(p) else { return }
        client.enqueue(data: data, entryType: .event, level: .info)
    }

    // MARK: - CaptureError

    public func captureError(_ error: Error, attributes: [String: String]? = nil) {
        guard let client = LogFlux._client else { return }
        var p = PayloadError(error: error)
        applyContext(&p)
        applyScope(&p.attributes)
        if let extraAttrs = attributes {
            if p.attributes == nil { p.attributes = [:] }
            for (k, v) in extraAttrs { p.attributes?[k] = v }
        }
        p.breadcrumbs = breadcrumbs.snapshot()

        guard let data = try? JSONEncoder().encode(p) else { return }
        client.enqueue(data: data, entryType: .log, level: .error)
    }

    // MARK: - Private

    private func scopedLog(level: LogLevel, message: String, extraAttrs: [String: String]?) {
        guard let client = LogFlux._client else { return }
        var p = PayloadLog(message: message, level: level.rawValue)
        applyContext(&p)
        applyScope(&p.attributes)
        if let extraAttrs = extraAttrs {
            if p.attributes == nil { p.attributes = [:] }
            for (k, v) in extraAttrs { p.attributes?[k] = v }
        }

        if level.rawValue <= LogLevel.info.rawValue {
            breadcrumbs.add(Breadcrumb(category: "log", message: message, level: level.label))
        }

        guard let data = try? JSONEncoder().encode(p) else { return }
        client.enqueue(data: data, entryType: .log, level: level)
    }

    /// Merges scope attributes into the payload's attributes (scope = defaults, don't overwrite).
    func applyScope(_ payloadAttrs: inout [String: String]?) {
        lock.lock()
        let attrsCopy = attributes
        lock.unlock()

        if attrsCopy.isEmpty { return }

        if payloadAttrs == nil {
            payloadAttrs = attrsCopy
        } else {
            for (k, v) in attrsCopy where payloadAttrs?[k] == nil {
                payloadAttrs?[k] = v
            }
        }
    }
}
