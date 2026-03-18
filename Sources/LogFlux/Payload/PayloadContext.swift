import Foundation

/// Global context that gets auto-attached to all payloads.
/// Thread-safe singleton, configured by LogFlux.initialize().
final class PayloadContext: @unchecked Sendable {
    static let shared = PayloadContext()

    private let lock = NSLock()
    private(set) var source: String = ""
    private(set) var environment: String = ""
    private(set) var release: String = ""

    private init() {}

    func configure(source: String, environment: String, release: String) {
        lock.lock()
        self.source = source
        self.environment = environment
        self.release = release
        lock.unlock()
    }

    func reset() {
        lock.lock()
        source = ""
        environment = ""
        release = ""
        lock.unlock()
    }

    /// Returns the default meta dictionary (environment + release) if any are set.
    func defaultMeta() -> [String: String]? {
        lock.lock()
        let env = environment
        let rel = release
        lock.unlock()

        if env.isEmpty && rel.isEmpty { return nil }
        var meta: [String: String] = [:]
        if !env.isEmpty { meta["environment"] = env }
        if !rel.isEmpty { meta["release"] = rel }
        return meta
    }

    /// Returns the configured source.
    func getSource() -> String {
        lock.lock()
        defer { lock.unlock() }
        return source
    }
}

/// Protocol for payloads that support context application.
protocol ContextApplicable {
    var source: String { get set }
    var meta: [String: String]? { get set }
}

extension PayloadLog: ContextApplicable {}
extension PayloadMetric: ContextApplicable {}
extension PayloadTrace: ContextApplicable {}
extension PayloadEvent: ContextApplicable {}
extension PayloadAudit: ContextApplicable {}
extension PayloadError: ContextApplicable {}
extension PayloadTelemetry: ContextApplicable {}

/// Apply global context (source, meta) to a payload.
func applyContext<T: ContextApplicable>(_ payload: inout T) {
    let ctx = PayloadContext.shared
    if payload.source.isEmpty {
        payload.source = ctx.getSource()
    }
    if let defaultMeta = ctx.defaultMeta() {
        if payload.meta == nil {
            payload.meta = defaultMeta
        } else {
            for (k, v) in defaultMeta where payload.meta?[k] == nil {
                payload.meta?[k] = v
            }
        }
    }
}
