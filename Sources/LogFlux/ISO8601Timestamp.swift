import Foundation

/// Thread-safe ISO 8601 timestamp formatting.
enum ISO8601Timestamp {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func now() -> String {
        formatter.string(from: Date())
    }

    static func format(_ date: Date) -> String {
        formatter.string(from: date)
    }
}
