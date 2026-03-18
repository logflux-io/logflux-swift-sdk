import Foundation

/// v2 Log payload (Entry Type 1).
public struct PayloadLog: Codable, Sendable {
    public var v: String = "2.0"
    public var type: String = "log"
    public var source: String
    public var level: Int
    public var ts: String
    public var message: String
    public var logger: String?
    public var attributes: [String: String]?
    public var meta: [String: String]?

    public init(source: String = "", message: String, level: Int) {
        self.source = source
        self.level = level
        self.ts = ISO8601Timestamp.now()
        self.message = message
    }
}
