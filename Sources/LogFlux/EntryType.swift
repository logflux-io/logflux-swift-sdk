import Foundation

/// Entry type constants matching the Go SDK.
public enum EntryType: Int, Sendable {
    case log              = 1
    case metric           = 2
    case trace            = 3
    case event            = 4
    case audit            = 5
    case telemetry        = 6
    case telemetryManaged = 7

    /// Whether the entry type requires E2E encryption (types 1-6).
    var requiresEncryption: Bool {
        rawValue >= 1 && rawValue <= 6
    }

    /// Default payload type for this entry type.
    var defaultPayloadType: Int {
        self == .telemetryManaged ? PayloadType.gzipJSON : PayloadType.aes256GCMGzipJSON
    }

    /// Pricing category for quota tracking.
    var category: String {
        switch self {
        case .log, .metric, .event:
            return "events"
        case .trace, .telemetry, .telemetryManaged:
            return "traces"
        case .audit:
            return "audit"
        }
    }
}

/// Payload type constants.
enum PayloadType {
    static let aes256GCMGzipJSON = 1  // AES-256-GCM + gzip (types 1-6)
    static let gzipJSON          = 3  // gzip only (type 7)
}
