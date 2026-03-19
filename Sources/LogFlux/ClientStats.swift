import Foundation

/// Runtime statistics for the LogFlux SDK.
public struct ClientStats: Sendable {
    public let entriesSent: Int
    public let entriesDropped: Int
    public let entriesQueued: Int
    public let dropReasons: [String: Int]
}
