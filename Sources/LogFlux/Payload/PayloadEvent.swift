import Foundation

/// v2 Event payload (Entry Type 4).
public struct PayloadEvent: Codable, Sendable {
    public var v: String = "2.0"
    public var type: String = "event"
    public var source: String
    public var level: Int = 7
    public var ts: String
    public var event: String
    public var attributes: [String: String]?
    public var meta: [String: String]?

    public init(source: String = "", event: String) {
        self.source = source
        self.ts = ISO8601Timestamp.now()
        self.event = event
    }
}
