import Foundation

/// v2 Error payload (sub-type of Log, Entry Type 1).
/// Includes stack trace, error chain, and breadcrumbs.
public struct PayloadError: Codable, Sendable {
    public var v: String = "2.0"
    public var type: String = "log"
    public var source: String
    public var level: Int = 4 // error
    public var ts: String
    public var message: String
    public var logger: String?
    public var errorType: String?
    public var errorChain: [ChainedError]?
    public var stackTrace: [StackFrame]?
    public var breadcrumbs: [Breadcrumb]?
    public var attributes: [String: String]?
    public var meta: [String: String]?

    enum CodingKeys: String, CodingKey {
        case v, type, source, level, ts, message, logger
        case errorType = "error_type"
        case errorChain = "error_chain"
        case stackTrace = "stack_trace"
        case breadcrumbs, attributes, meta
    }

    public init(source: String = "", error: Error) {
        self.source = source
        self.ts = ISO8601Timestamp.now()
        self.message = error.localizedDescription
        self.errorType = String(describing: Swift.type(of: error))
        self.stackTrace = StackFrame.capture()
    }

    public init(source: String = "", error: Error, message: String) {
        self.source = source
        self.ts = ISO8601Timestamp.now()
        self.message = message
        self.errorType = String(describing: Swift.type(of: error))
        self.attributes = ["error": error.localizedDescription]
        self.stackTrace = StackFrame.capture()
    }
}

/// One error in an unwrapped chain.
public struct ChainedError: Codable, Sendable {
    public var type: String
    public var message: String

    public init(type: String, message: String) {
        self.type = type
        self.message = message
    }
}

/// A single frame in a stack trace.
public struct StackFrame: Codable, Sendable {
    public var function: String
    public var file: String?
    public var line: Int?

    public init(function: String, file: String? = nil, line: Int? = nil) {
        self.function = function
        self.file = file
        self.line = line
    }

    /// Capture the current call stack as stack frames.
    static func capture() -> [StackFrame] {
        let symbols = Thread.callStackSymbols
        // Skip the first few frames (capture, PayloadError init, caller)
        let relevantSymbols = symbols.dropFirst(3).prefix(20)
        return relevantSymbols.map { symbol in
            StackFrame(function: symbol)
        }
    }
}
