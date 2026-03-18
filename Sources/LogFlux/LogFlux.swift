import Foundation

/// LogFlux Swift SDK - privacy-friendly telemetry with end-to-end encryption.
///
/// Usage:
/// ```swift
/// try LogFlux.initialize(options: Options(apiKey: "eu-lf_xxxxx"))
/// LogFlux.info("Server started", attributes: ["port": "8080"])
/// LogFlux.event("User.Login", attributes: ["method": "oauth"])
/// LogFlux.audit("delete", actor: "usr_123", resource: "document", resourceID: "doc_456")
/// LogFlux.flush(timeout: 5)
/// LogFlux.close()
/// ```
public enum LogFlux {
    /// Internal client reference (visible to Scope/Span via `internal`).
    internal static var _client: LogFluxClient?
    private static let lock = NSLock()
    private static var hooks = SendHooks()

    // MARK: - Initialization

    /// Initialize the SDK with options. Call once at app startup.
    public static func initialize(options: Options) throws {
        lock.lock()
        defer { lock.unlock() }
        guard _client == nil else { return }

        try options.validateAPIKey()

        // Configure global payload context
        let source = options.source.isEmpty ? options.node : options.source
        PayloadContext.shared.configure(
            source: source,
            environment: options.environment,
            release: options.release
        )

        // Store hooks
        hooks = SendHooks(
            log: options.beforeSendLog,
            error: options.beforeSendError,
            metric: options.beforeSendMetric,
            event: options.beforeSendEvent,
            audit: options.beforeSendAudit,
            trace: options.beforeSendTrace,
            telemetry: options.beforeSendTelemetry
        )

        let client = LogFluxClient(options: options)
        _client = client
        client.start()
    }

    /// Initialize from environment variables.
    public static func initFromEnvironment(node: String) throws {
        let opts = try Options.fromEnvironment(node: node)
        try initialize(options: opts)
    }

    /// Shut down the SDK. Flushes remaining entries and stops all activity.
    public static func close() {
        lock.lock()
        let client = _client
        _client = nil
        hooks = SendHooks()
        lock.unlock()

        client?.flush(timeout: 10)
        client?.stop()
        PayloadContext.shared.reset()
    }

    /// Synchronous flush for app termination. Blocks for up to `timeout` seconds.
    public static func flush(timeout: TimeInterval = 5.0) {
        _client?.flush(timeout: timeout)
    }

    /// Whether the SDK is initialized and active.
    public static var isActive: Bool {
        _client != nil
    }

    // MARK: - Log (Type 1) - 8 severity levels

    public static func debug(_ message: String, attributes: [String: String]? = nil) {
        log(level: .debug, message, attributes: attributes)
    }

    public static func info(_ message: String, attributes: [String: String]? = nil) {
        log(level: .info, message, attributes: attributes)
    }

    public static func notice(_ message: String, attributes: [String: String]? = nil) {
        log(level: .notice, message, attributes: attributes)
    }

    public static func warn(_ message: String, attributes: [String: String]? = nil) {
        log(level: .warning, message, attributes: attributes)
    }

    public static func error(_ message: String, attributes: [String: String]? = nil) {
        log(level: .error, message, attributes: attributes)
    }

    public static func critical(_ message: String, attributes: [String: String]? = nil) {
        log(level: .critical, message, attributes: attributes)
    }

    public static func alert(_ message: String, attributes: [String: String]? = nil) {
        log(level: .alert, message, attributes: attributes)
    }

    public static func emergency(_ message: String, attributes: [String: String]? = nil) {
        log(level: .emergency, message, attributes: attributes)
    }

    /// Sends a critical log and then calls exit(1), matching Go SDK Fatal behavior.
    public static func fatal(_ message: String, attributes: [String: String]? = nil) {
        log(level: .critical, message, attributes: attributes)
        flush(timeout: 5)
        exit(1)
    }

    public static func log(level: LogLevel, _ message: String, attributes: [String: String]? = nil) {
        guard let client = _client else { return }

        var p = PayloadLog(message: message, level: level.rawValue)
        applyContext(&p)
        if let attrs = attributes { p.attributes = mergeAttributes(p.attributes, attrs) }

        // BeforeSend hook
        if let hook = hooks.log {
            guard let result = hook(&p) else {
                client.enqueue(data: Data(), entryType: .log, level: level) // dropped by hook
                return
            }
            p = result
        }

        // Auto-breadcrumb for info level and above (lower numeric = higher severity)
        if level.rawValue <= LogLevel.info.rawValue {
            client.addBreadcrumb(Breadcrumb(category: "log", message: message, level: level.label))
        }

        guard let data = try? JSONEncoder().encode(p) else { return }
        client.enqueue(data: data, entryType: .log, level: level)
    }

    // MARK: - Metric (Type 2)

    public static func counter(_ name: String, value: Double, attributes: [String: String]? = nil) {
        metric(name, value: value, metricType: "counter", attributes: attributes)
    }

    public static func gauge(_ name: String, value: Double, attributes: [String: String]? = nil) {
        metric(name, value: value, metricType: "gauge", attributes: attributes)
    }

    public static func metric(_ name: String, value: Double, metricType: String, attributes: [String: String]? = nil) {
        guard let client = _client else { return }

        var p = PayloadMetric(name: name, value: value, kind: metricType)
        applyContext(&p)
        if let attrs = attributes { p.attributes = mergeAttributes(p.attributes, attrs) }

        if let hook = hooks.metric {
            guard let result = hook(&p) else { return }
            p = result
        }

        guard let data = try? JSONEncoder().encode(p) else { return }
        client.enqueue(data: data, entryType: .metric, level: .info)
    }

    // MARK: - Event (Type 4)

    public static func event(_ name: String, attributes: [String: String]? = nil) {
        guard let client = _client else { return }

        var p = PayloadEvent(event: name)
        applyContext(&p)
        if let attrs = attributes { p.attributes = mergeAttributes(p.attributes, attrs) }

        if let hook = hooks.event {
            guard let result = hook(&p) else { return }
            p = result
        }

        // Auto-breadcrumb for events
        client.addBreadcrumb(Breadcrumb(category: "event", message: name, data: attributes))

        guard let data = try? JSONEncoder().encode(p) else { return }
        client.enqueue(data: data, entryType: .event, level: .info)
    }

    // MARK: - Audit (Type 5)

    public static func audit(
        _ action: String,
        actor: String,
        resource: String,
        resourceID: String,
        attributes: [String: String]? = nil
    ) {
        guard let client = _client else { return }
        // Audit entries are never sampled - compliance requirement (handled in client.enqueue)

        var p = PayloadAudit(action: action, actor: actor, resource: resource, resourceID: resourceID)
        applyContext(&p)
        if let attrs = attributes { p.attributes = mergeAttributes(p.attributes, attrs) }

        if let hook = hooks.audit {
            guard let result = hook(&p) else { return }
            p = result
        }

        guard let data = try? JSONEncoder().encode(p) else { return }
        client.enqueue(data: data, entryType: .audit, level: .notice)
    }

    // MARK: - Error capture

    public static func captureError(_ error: Error, attributes: [String: String]? = nil) {
        guard let client = _client else { return }

        var p = PayloadError(error: error)
        applyContext(&p)
        if let attrs = attributes { p.attributes = mergeAttributes(p.attributes, attrs) }
        p.breadcrumbs = client.breadcrumbSnapshot()

        if let hook = hooks.error {
            guard let result = hook(&p) else { return }
            p = result
        }

        guard let data = try? JSONEncoder().encode(p) else { return }
        client.enqueue(data: data, entryType: .log, level: .error)
    }

    public static func captureErrorWithMessage(_ error: Error, message: String, attributes: [String: String]? = nil) {
        guard let client = _client else { return }

        var p = PayloadError(error: error, message: message)
        applyContext(&p)
        if let attrs = attributes { p.attributes = mergeAttributes(p.attributes, attrs) }
        p.breadcrumbs = client.breadcrumbSnapshot()

        if let hook = hooks.error {
            guard let result = hook(&p) else { return }
            p = result
        }

        guard let data = try? JSONEncoder().encode(p) else { return }
        client.enqueue(data: data, entryType: .log, level: .error)
    }

    // MARK: - Breadcrumbs

    public static func addBreadcrumb(_ category: String, _ message: String, data: [String: String]? = nil) {
        _client?.addBreadcrumb(Breadcrumb(category: category, message: message, data: data))
    }

    public static func clearBreadcrumbs() {
        _client?.clearBreadcrumbs()
    }

    // MARK: - Scopes

    /// Runs a block with an isolated scope for per-request context.
    public static func withScope(_ block: (Scope) -> Void) {
        let scope = Scope(maxBreadcrumbs: _client?.options.maxBreadcrumbs ?? 100)
        block(scope)
    }

    // MARK: - Tracing

    /// Creates and starts a new root span (generates new trace ID).
    public static func startSpan(_ operation: String, _ description: String? = nil) -> Span {
        Span(operation: operation, description: description)
    }

    /// Creates a child span that continues a trace from incoming headers.
    /// If no trace header is present, starts a new root span.
    public static func continueFromRequest(
        _ headers: [String: String],
        operation: String,
        description: String? = nil
    ) -> Span {
        // Parse X-LogFlux-Trace header: <trace_id>-<span_id>-<sampled>
        if let traceHeader = headers["X-LogFlux-Trace"] ?? headers["x-logflux-trace"] {
            let parts = traceHeader.split(separator: "-", maxSplits: 2)
            if parts.count >= 2 {
                let traceID = String(parts[0])
                let parentSpanID = String(parts[1])
                if traceID.count == 32, parentSpanID.count == 16 {
                    return Span(
                        traceID: traceID,
                        parentSpanID: parentSpanID,
                        operation: operation,
                        description: description
                    )
                }
            }
        }
        return startSpan(operation, description)
    }

    // MARK: - Stats

    public static func stats() -> ClientStats {
        _client?.getStats() ?? ClientStats(entriesSent: 0, entriesDropped: 0, entriesQueued: 0, dropReasons: [:])
    }

    // MARK: - Testing

    /// Reset for testing. Only available in debug builds.
    internal static func reset() {
        close()
        KeychainStore.delete()
    }

    // MARK: - Helpers

    private static func mergeAttributes(_ existing: [String: String]?, _ new: [String: String]) -> [String: String] {
        var merged = existing ?? [:]
        for (k, v) in new { merged[k] = v }
        return merged
    }
}

// MARK: - SendHooks

/// Typed BeforeSend callbacks. Return nil to drop the entry.
private struct SendHooks {
    var log: ((@Sendable (inout PayloadLog) -> PayloadLog?))? = nil
    var error: ((@Sendable (inout PayloadError) -> PayloadError?))? = nil
    var metric: ((@Sendable (inout PayloadMetric) -> PayloadMetric?))? = nil
    var event: ((@Sendable (inout PayloadEvent) -> PayloadEvent?))? = nil
    var audit: ((@Sendable (inout PayloadAudit) -> PayloadAudit?))? = nil
    var trace: ((@Sendable (inout PayloadTrace) -> PayloadTrace?))? = nil
    var telemetry: ((@Sendable (inout PayloadTelemetry) -> PayloadTelemetry?))? = nil
}
