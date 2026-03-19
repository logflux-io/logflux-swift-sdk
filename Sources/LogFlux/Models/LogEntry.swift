import Foundation

/// Internal representation of an entry ready for encryption and transmission.
/// The data field contains the serialized v2 payload (JSON bytes).
struct LogEntry: Codable, Sendable {
    let data: Data
    let entryType: Int
    let level: Int
    let timestamp: String

    init(data: Data, entryType: EntryType, level: LogLevel) {
        self.data = data
        self.entryType = entryType.rawValue
        self.level = level.rawValue
        self.timestamp = ISO8601Timestamp.now()
    }
}
