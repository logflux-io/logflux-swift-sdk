import Foundation

/// v2 Metric payload (Entry Type 2).
public struct PayloadMetric: Codable, Sendable {
    public var v: String = "2.0"
    public var type: String = "metric"
    public var source: String
    public var level: Int = 7
    public var ts: String
    public var name: String
    public var value: Double
    public var kind: String
    public var unit: String?
    public var attributes: [String: String]?
    public var meta: [String: String]?

    public init(source: String = "", name: String, value: Double, kind: String, unit: String? = nil) {
        self.source = source
        self.ts = ISO8601Timestamp.now()
        self.name = name
        self.value = value
        self.kind = kind
        self.unit = unit
    }
}
