import Foundation

/// Configuration for the LogFlux SDK. Matches Go SDK options.
public struct Options: Sendable {
    /// LogFlux API key (format: "<region>-lf_<key>").
    public var apiKey: String

    /// Source identifier for all entries (e.g., "com.example.app").
    public var source: String

    /// Environment tag (e.g., "production", "staging").
    public var environment: String

    /// Release/version tag.
    public var release: String

    /// Node name for identification.
    public var node: String

    // MARK: - Transport

    /// Direct ingestor URL. Highest priority (skips zone and discovery).
    public var customEndpointURL: String?

    /// Ingestor zone (e.g., "eu", "us", "ca", "au", "ap").
    public var zone: String?

    /// Log group override.
    public var logGroup: String?

    // MARK: - Queue & workers

    /// Maximum entries in the queue (default: 1000).
    public var queueSize: Int

    /// Interval between automatic flushes in seconds (default: 5).
    public var flushInterval: TimeInterval

    /// Maximum entries per batch (default: 100).
    public var batchSize: Int

    /// Number of background worker tasks (default: 2).
    public var workerCount: Int

    // MARK: - Retry

    /// Maximum number of retries per batch (default: 3).
    public var maxRetries: Int

    /// Initial retry delay in seconds (default: 1).
    public var initialDelay: TimeInterval

    /// Maximum retry delay in seconds (default: 30).
    public var maxDelay: TimeInterval

    /// Backoff multiplier (default: 2.0).
    public var backoffFactor: Double

    // MARK: - Behavior

    /// HTTP request timeout in seconds (default: 30).
    public var httpTimeout: TimeInterval

    /// If true, never throw from log methods (default: true).
    public var failsafe: Bool

    /// Enable gzip compression before encryption (default: true).
    public var enableCompression: Bool

    /// Sample rate 0.0-1.0; 1.0 = send all (default: 1.0). Audit entries exempt.
    public var sampleRate: Double

    /// Maximum breadcrumbs to keep (default: 100).
    public var maxBreadcrumbs: Int

    /// Enable debug logging to os.log (default: false).
    public var debug: Bool

    // MARK: - BeforeSend hooks (return nil to drop)

    /// Per-type hooks. Return nil to drop the entry before encryption.
    public var beforeSendLog: (@Sendable (inout PayloadLog) -> PayloadLog?)?
    public var beforeSendError: (@Sendable (inout PayloadError) -> PayloadError?)?
    public var beforeSendMetric: (@Sendable (inout PayloadMetric) -> PayloadMetric?)?
    public var beforeSendEvent: (@Sendable (inout PayloadEvent) -> PayloadEvent?)?
    public var beforeSendAudit: (@Sendable (inout PayloadAudit) -> PayloadAudit?)?
    public var beforeSendTrace: (@Sendable (inout PayloadTrace) -> PayloadTrace?)?
    public var beforeSendTelemetry: (@Sendable (inout PayloadTelemetry) -> PayloadTelemetry?)?

    public init(apiKey: String) {
        self.apiKey = apiKey
        self.source = ""
        self.environment = ""
        self.release = ""
        self.node = ""
        self.queueSize = 1000
        self.flushInterval = 5
        self.batchSize = 100
        self.workerCount = 2
        self.maxRetries = 3
        self.initialDelay = 1
        self.maxDelay = 30
        self.backoffFactor = 2.0
        self.httpTimeout = 30
        self.failsafe = true
        self.enableCompression = true
        self.sampleRate = 1.0
        self.maxBreadcrumbs = 100
        self.debug = false
    }

    /// Validates the API key format: <region>-lf_<key>.
    func validateAPIKey() throws {
        let parts = apiKey.split(separator: "-", maxSplits: 1)
        guard parts.count == 2 else {
            throw LogFluxError.invalidAPIKey("must be <region>-lf_<key>")
        }
        let region = String(parts[0])
        let validRegions = Set(["eu", "us", "ca", "au", "ap"])
        guard validRegions.contains(region) else {
            throw LogFluxError.invalidAPIKey("invalid region: \(region)")
        }
        let keyPart = String(parts[1])
        guard keyPart.hasPrefix("lf_") else {
            throw LogFluxError.invalidAPIKey("key must start with lf_")
        }
        guard keyPart.count > 3 else {
            throw LogFluxError.invalidAPIKey("key body is empty")
        }
    }

    /// Extracts the region from the API key.
    func extractRegion() -> String? {
        let parts = apiKey.split(separator: "-", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return String(parts[0])
    }

    /// Loads options from environment variables, matching Go SDK env vars.
    public static func fromEnvironment(node: String) throws -> Options {
        guard let apiKey = ProcessInfo.processInfo.environment["LOGFLUX_API_KEY"], !apiKey.isEmpty else {
            throw LogFluxError.missingAPIKey
        }

        var opts = Options(apiKey: apiKey)
        opts.node = node

        let env = ProcessInfo.processInfo.environment

        if let v = env["LOGFLUX_ENVIRONMENT"] { opts.environment = v }
        if let v = env["LOGFLUX_NODE"], !v.isEmpty { opts.node = v }
        if let v = env["LOGFLUX_SOURCE"] { opts.source = v }
        if let v = env["LOGFLUX_RELEASE"] { opts.release = v }
        if let v = env["LOGFLUX_LOG_GROUP"] { opts.logGroup = v }
        if let v = env["LOGFLUX_CUSTOM_ENDPOINT"] { opts.customEndpointURL = v }

        if let v = env["LOGFLUX_QUEUE_SIZE"], let n = Int(v), n > 0 { opts.queueSize = n }
        if let v = env["LOGFLUX_BATCH_SIZE"], let n = Int(v), n > 0 { opts.batchSize = n }
        if let v = env["LOGFLUX_WORKER_COUNT"], let n = Int(v), n > 0 { opts.workerCount = n }
        if let v = env["LOGFLUX_FLUSH_INTERVAL"], let n = TimeInterval(v), n > 0 { opts.flushInterval = n }
        if let v = env["LOGFLUX_HTTP_TIMEOUT"], let n = TimeInterval(v), n > 0 { opts.httpTimeout = n }
        if let v = env["LOGFLUX_MAX_RETRIES"], let n = Int(v), n > 0 { opts.maxRetries = n }
        if let v = env["LOGFLUX_SAMPLE_RATE"], let n = Double(v) { opts.sampleRate = max(0, min(1, n)) }
        if let v = env["LOGFLUX_MAX_BREADCRUMBS"], let n = Int(v), n > 0 { opts.maxBreadcrumbs = n }

        if let v = env["LOGFLUX_ENABLE_COMPRESSION"] {
            opts.enableCompression = (v.lowercased() == "true" || v == "1")
        }
        if let v = env["LOGFLUX_DEBUG"] {
            opts.debug = (v.lowercased() == "true" || v == "1")
        }

        return opts
    }
}

/// Errors thrown by LogFlux initialization.
public enum LogFluxError: Error, LocalizedError {
    case invalidAPIKey(String)
    case missingAPIKey
    case alreadyInitialized
    case notInitialized

    public var errorDescription: String? {
        switch self {
        case .invalidAPIKey(let reason): return "Invalid API key: \(reason)"
        case .missingAPIKey: return "LOGFLUX_API_KEY environment variable is required"
        case .alreadyInitialized: return "LogFlux is already initialized"
        case .notInitialized: return "LogFlux is not initialized"
        }
    }
}
