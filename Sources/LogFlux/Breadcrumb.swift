import Foundation

/// A single entry in the breadcrumb trail.
public struct Breadcrumb: Codable, Sendable {
    public let timestamp: String
    public let category: String
    public let message: String
    public let level: String?
    public let data: [String: String]?

    public init(
        timestamp: String? = nil,
        category: String,
        message: String,
        level: String? = nil,
        data: [String: String]? = nil
    ) {
        self.timestamp = timestamp ?? ISO8601Timestamp.now()
        self.category = category
        self.message = message
        self.level = level
        self.data = data
    }
}

/// Thread-safe ring buffer of breadcrumbs.
final class BreadcrumbRing: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Breadcrumb?]
    private let maxSize: Int
    private var position: Int = 0
    private var full: Bool = false

    init(maxSize: Int = 100) {
        self.maxSize = max(maxSize, 1)
        self.items = [Breadcrumb?](repeating: nil, count: self.maxSize)
    }

    func add(_ breadcrumb: Breadcrumb) {
        lock.lock()
        items[position] = breadcrumb
        position = (position + 1) % maxSize
        if position == 0 {
            full = true
        }
        lock.unlock()
    }

    /// Returns a chronological copy of all breadcrumbs.
    func snapshot() -> [Breadcrumb] {
        lock.lock()
        defer { lock.unlock() }

        let count = full ? maxSize : position
        if count == 0 { return [] }

        var result: [Breadcrumb] = []
        result.reserveCapacity(count)

        if full {
            // Oldest entries start at position (wrapped around)
            for i in 0..<maxSize {
                let idx = (position + i) % maxSize
                if let item = items[idx] {
                    result.append(item)
                }
            }
        } else {
            for i in 0..<position {
                if let item = items[i] {
                    result.append(item)
                }
            }
        }
        return result
    }

    func clear() {
        lock.lock()
        position = 0
        full = false
        for i in 0..<items.count {
            items[i] = nil
        }
        lock.unlock()
    }

    var size: Int {
        lock.lock()
        defer { lock.unlock() }
        return full ? maxSize : position
    }
}
