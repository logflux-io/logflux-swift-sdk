import Foundation

/// File-based persistent queue for LogEntries.
/// Each entry is stored as a separate file in the queue directory.
/// Files are named with ascending integers for FIFO ordering.
final class DiskQueue: @unchecked Sendable {
    private let directory: URL
    private let maxSize: Int
    private let lock = NSLock()
    private var counter: UInt64

    init(maxSize: Int = 1000, directory: URL? = nil) {
        self.maxSize = maxSize

        if let directory {
            self.directory = directory
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            self.directory = caches.appendingPathComponent("io.logflux.queue", isDirectory: true)
        }
        self.counter = 0

        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)

        // Initialize counter from existing files
        let existing = Self.sortedFiles(in: self.directory)
        if let last = existing.last,
           let num = Self.fileNumber(last) {
            self.counter = num
        }
    }

    /// Enqueue entries to disk. Thread-safe.
    func enqueue(_ entries: [LogEntry]) {
        lock.lock()
        defer { lock.unlock() }

        let encoder = JSONEncoder()
        for entry in entries {
            guard let data = try? encoder.encode(entry) else { continue }
            counter += 1
            let file = directory.appendingPathComponent("\(counter).dat")
            try? data.write(to: file, options: .atomic)
        }
        evictIfNeeded()
    }

    /// Dequeue up to `limit` entries. Removes them from disk. Thread-safe.
    func dequeue(limit: Int) -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }

        let files = Self.sortedFiles(in: directory)
        let batch = Array(files.prefix(limit))
        guard !batch.isEmpty else { return [] }

        let decoder = JSONDecoder()
        var entries: [LogEntry] = []

        for file in batch {
            let path = directory.appendingPathComponent(file)
            if let data = try? Data(contentsOf: path),
               let entry = try? decoder.decode(LogEntry.self, from: data) {
                entries.append(entry)
            }
            try? FileManager.default.removeItem(at: path)
        }

        return entries
    }

    /// Number of queued entries.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.count ?? 0
    }

    /// Peek without removing.
    var isEmpty: Bool {
        count == 0
    }

    /// Clear all queued entries.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    // MARK: - Internal

    private func evictIfNeeded() {
        let files = Self.sortedFiles(in: directory)
        guard files.count > maxSize else { return }

        let excess = files.prefix(files.count - maxSize)
        for file in excess {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    private static func sortedFiles(in dir: URL) -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files
            .filter { $0.hasSuffix(".dat") }
            .sorted { fileNumber($0) ?? 0 < fileNumber($1) ?? 0 }
    }

    private static func fileNumber(_ filename: String) -> UInt64? {
        let name = filename.replacingOccurrences(of: ".dat", with: "")
        return UInt64(name)
    }
}
