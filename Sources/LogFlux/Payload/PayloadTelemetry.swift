import Foundation

/// v2 Telemetry payload (Entry Type 6/7).
public struct PayloadTelemetry: Codable, Sendable {
    public var v: String = "2.0"
    public var type: String = "telemetry"
    public var source: String
    public var level: Int = 7
    public var ts: String
    public var deviceID: String?
    public var readings: [Reading]?
    public var attributes: [String: String]?
    public var meta: [String: String]?

    enum CodingKeys: String, CodingKey {
        case v, type, source, level, ts
        case deviceID = "device_id"
        case readings, attributes, meta
    }

    public init(source: String = "", deviceID: String? = nil, readings: [Reading]? = nil) {
        self.source = source
        self.ts = ISO8601Timestamp.now()
        self.deviceID = deviceID
        self.readings = readings
    }
}

/// A single sensor measurement.
public struct Reading: Codable, Sendable {
    public var name: String
    public var value: Double
    public var unit: String?

    public init(name: String, value: Double, unit: String? = nil) {
        self.name = name
        self.value = value
        self.unit = unit
    }
}
