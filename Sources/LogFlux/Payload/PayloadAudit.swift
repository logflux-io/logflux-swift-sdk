import Foundation

/// v2 Audit payload (Entry Type 5, Object Lock).
public struct PayloadAudit: Codable, Sendable {
    public var v: String = "2.0"
    public var type: String = "audit"
    public var source: String
    public var level: Int = 6
    public var ts: String
    public var action: String
    public var actor: String
    public var actorType: String?
    public var resource: String
    public var resourceID: String
    public var outcome: String = "success"
    public var attributes: [String: String]?
    public var meta: [String: String]?

    enum CodingKeys: String, CodingKey {
        case v, type, source, level, ts, action, actor
        case actorType = "actor_type"
        case resource
        case resourceID = "resource_id"
        case outcome, attributes, meta
    }

    public init(source: String = "", action: String, actor: String, resource: String, resourceID: String) {
        self.source = source
        self.ts = ISO8601Timestamp.now()
        self.action = action
        self.actor = actor
        self.resource = resource
        self.resourceID = resourceID
    }
}
