import Foundation

/// Syslog severity levels (1-8), matching the Go SDK constants.
public enum LogLevel: Int, Sendable, Comparable {
    case emergency = 1
    case alert     = 2
    case critical  = 3
    case error     = 4
    case warning   = 5
    case notice    = 6
    case info      = 7
    case debug     = 8

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Human-readable string for breadcrumb levels.
    var label: String {
        switch self {
        case .emergency, .alert, .critical, .error:
            return "error"
        case .warning:
            return "warning"
        case .notice, .info, .debug:
            return "info"
        }
    }
}
