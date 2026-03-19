import Foundation

/// v2 Trace payload (Entry Type 3).
public struct PayloadTrace: Codable, Sendable {
    public var v: String = "2.0"
    public var type: String = "trace"
    public var source: String
    public var level: Int = 7
    public var ts: String
    public var traceID: String
    public var spanID: String
    public var parentSpanID: String?
    public var operation: String
    public var name: String?
    public var startTime: String
    public var endTime: String?
    public var durationMs: Int64?
    public var status: String = "ok"
    public var attributes: [String: String]?
    public var meta: [String: String]?

    enum CodingKeys: String, CodingKey {
        case v, type, source, level, ts
        case traceID = "trace_id"
        case spanID = "span_id"
        case parentSpanID = "parent_span_id"
        case operation, name
        case startTime = "start_time"
        case endTime = "end_time"
        case durationMs = "duration_ms"
        case status, attributes, meta
    }

    public init(
        source: String = "",
        traceID: String,
        spanID: String,
        parentSpanID: String? = nil,
        operation: String,
        name: String? = nil,
        startTime: Date,
        endTime: Date
    ) {
        self.source = source
        self.ts = ISO8601Timestamp.now()
        self.traceID = traceID
        self.spanID = spanID
        self.parentSpanID = parentSpanID
        self.operation = operation
        self.name = name
        self.startTime = ISO8601Timestamp.format(startTime)
        self.endTime = ISO8601Timestamp.format(endTime)
        self.durationMs = Int64(endTime.timeIntervalSince(startTime) * 1000)
    }
}
