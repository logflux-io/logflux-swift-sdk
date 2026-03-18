import CryptoKit
import Foundation
import os.log

/// Drop reason constants for stats tracking.
enum DropReason: String {
    case queueOverflow  = "queue_overflow"
    case networkError   = "network_error"
    case sendError      = "send_error"
    case rateLimited    = "ratelimit_backoff"
    case quotaExceeded  = "quota_exceeded"
    case beforeSend     = "before_send"
    case validationError = "validation_error"
    case sampled        = "sampled"
}

/// Core LogFlux client. Manages buffering, encryption, handshake lifecycle,
/// disk persistence, multipart sending, rate limiting, quota tracking, and stats.
///
/// Threading model:
/// - `enqueue()` accepts entries from any thread via lock-protected buffer
/// - Background workers drain the queue and send multipart/mixed batches
/// - Timer fires on a background queue, triggering flush
final class LogFluxClient: @unchecked Sendable {
    let options: Options
    private let logger: Logger

    // Buffer: lock-protected
    private let bufferLock = NSLock()
    private var buffer: [LogEntry] = []

    // Transport queue for all I/O
    private let transportQueue = DispatchQueue(label: "io.logflux.transport", qos: .utility)
    private var flushTimer: DispatchSourceTimer?

    // Worker management
    private var workerTasks: [Task<Void, Never>] = []

    // Encryption state (lock-protected)
    private let stateLock = NSLock()
    private var aesKey: SymmetricKey?
    private var keyID: String?
    private var ingestorURL: String?
    private var maxBatchSize: Int = 100

    // Lifecycle
    private var isStarted = false
    private var isHandshaking = false
    private var retryDelay: TimeInterval = 0.1

    // Components
    private let diskQueue: DiskQueue
    private let reachability = ReachabilityMonitor()
    private let breadcrumbs: BreadcrumbRing
    private let sampler: Sampler

    // Stats (lock-protected)
    private let statsLock = NSLock()
    private var totalSent: Int = 0
    private var totalDropped: Int = 0
    private var totalQueued: Int = 0
    private var dropReasons: [String: Int] = [:]

    // Rate limit state
    private let rateLimitLock = NSLock()
    private var rateLimitPauseUntil: Date = .distantPast

    // Quota state - per-category blocked
    private let quotaLock = NSLock()
    private var quotaBlocked: Set<String> = []

    // Closed flag
    private var closed = false

    init(options: Options) {
        self.options = options
        self.logger = Logger(subsystem: "io.logflux.sdk", category: "Client")
        self.diskQueue = DiskQueue(maxSize: options.queueSize)
        self.breadcrumbs = BreadcrumbRing(maxSize: options.maxBreadcrumbs)
        self.sampler = Sampler(rate: options.sampleRate)
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true

        // Try loading cached session from Keychain
        if let session = KeychainStore.load(),
           let keyData = Data(base64Encoded: session.aesKeyBase64), keyData.count == 32 {
            stateLock.lock()
            aesKey = AESEncryptor.importKey(keyData)
            keyID = session.keyID
            ingestorURL = session.ingestorURL
            maxBatchSize = session.maxBatchSize
            stateLock.unlock()

            if options.debug {
                logger.info("Loaded cached session, keyID=\(session.keyID.prefix(8))...")
            }
            startFlushTimer()
            startReachability()
            // Flush any entries left from a previous session
            transportQueue.async { [weak self] in self?.sendDiskQueue() }
            return
        }

        // No cached session - discover + handshake
        if options.debug {
            logger.info("No cached session, starting handshake")
        }
        startReachability()
        performHandshakeAsync()
    }

    func stop() {
        closed = true
        isStarted = false
        flushTimer?.cancel()
        flushTimer = nil
        reachability.stop()
        for task in workerTasks {
            task.cancel()
        }
        workerTasks.removeAll()

        // Zero key material
        stateLock.lock()
        aesKey = nil
        keyID = nil
        stateLock.unlock()
    }

    /// Synchronous flush for app termination. Blocks up to `timeout` seconds.
    func flush(timeout: TimeInterval) {
        let semaphore = DispatchSemaphore(value: 0)

        transportQueue.async { [weak self] in
            guard let self else { semaphore.signal(); return }
            self.flushBuffer()
            self.sendDiskQueue()
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + timeout)
    }

    // MARK: - Enqueue

    /// Enqueue a serialized payload for encryption and sending.
    func enqueue(data: Data, entryType: EntryType, level: LogLevel) {
        guard !closed else { return }

        // Sampling check (audit entries are never sampled)
        if entryType != .audit && !sampler.shouldSample() {
            recordDrop(.sampled, count: 1)
            return
        }

        // Quota check
        quotaLock.lock()
        let blocked = quotaBlocked.contains(entryType.category)
        quotaLock.unlock()
        if blocked {
            recordDrop(.quotaExceeded, count: 1)
            return
        }

        let entry = LogEntry(data: data, entryType: entryType, level: level)

        bufferLock.lock()
        let batchSize = maxBatchSize
        buffer.append(entry)
        let shouldFlush = buffer.count >= batchSize
        bufferLock.unlock()

        statsLock.lock()
        totalQueued += 1
        statsLock.unlock()

        if shouldFlush {
            transportQueue.async { [weak self] in self?.flushBuffer() }
        }
    }

    // MARK: - Breadcrumbs

    func addBreadcrumb(_ breadcrumb: Breadcrumb) {
        breadcrumbs.add(breadcrumb)
    }

    func clearBreadcrumbs() {
        breadcrumbs.clear()
    }

    func breadcrumbSnapshot() -> [Breadcrumb] {
        breadcrumbs.snapshot()
    }

    // MARK: - Stats

    func getStats() -> ClientStats {
        statsLock.lock()
        let sent = totalSent
        let dropped = totalDropped
        let queued = totalQueued
        let reasons = dropReasons
        statsLock.unlock()

        return ClientStats(
            entriesSent: sent,
            entriesDropped: dropped,
            entriesQueued: queued,
            dropReasons: reasons
        )
    }

    // MARK: - Flush & Send

    private func flushBuffer() {
        // Take all entries from buffer
        bufferLock.lock()
        let entries = buffer
        buffer.removeAll(keepingCapacity: true)
        bufferLock.unlock()

        guard !entries.isEmpty else { return }

        // Check if we have encryption keys
        stateLock.lock()
        let hasKey = aesKey != nil
        stateLock.unlock()

        guard hasKey else {
            // No session yet - put entries back
            bufferLock.lock()
            buffer.insert(contentsOf: entries, at: 0)
            // Cap buffer to prevent unbounded growth
            if buffer.count > options.queueSize {
                let overflow = buffer.count - options.queueSize
                buffer.removeFirst(overflow)
                bufferLock.unlock()
                recordDrop(.queueOverflow, count: overflow)
            } else {
                bufferLock.unlock()
            }
            return
        }

        // Write to disk queue first (durability), then try to send
        diskQueue.enqueue(entries)
        sendDiskQueue()
    }

    private func sendDiskQueue() {
        stateLock.lock()
        let url = ingestorURL
        let key = aesKey
        let kid = keyID
        let compress = options.enableCompression
        stateLock.unlock()

        guard let url, !url.isEmpty, let key, let kid else { return }
        guard reachability.isConnected else { return }

        // Rate limit pre-flight
        rateLimitLock.lock()
        let pauseUntil = rateLimitPauseUntil
        rateLimitLock.unlock()
        if Date() < pauseUntil { return }

        while true {
            let batch = diskQueue.dequeue(limit: maxBatchSize)
            guard !batch.isEmpty else { break }

            // Build multipart body
            let prepared = batch.map { entry in
                MultipartBuilder.PreparedEntry(
                    data: entry.data,
                    entryType: EntryType(rawValue: entry.entryType) ?? .log,
                    level: LogLevel(rawValue: entry.level) ?? .info
                )
            }

            let sendResult: SendResult
            do {
                let (body, contentType) = try MultipartBuilder.build(
                    entries: prepared,
                    aesKey: key,
                    keyID: kid,
                    enableCompression: compress
                )
                sendResult = sendBatchSync(body: body, contentType: contentType, ingestorURL: url)
            } catch {
                // Encryption failed - re-enqueue and retry later
                diskQueue.enqueue(batch)
                recordDrop(.sendError, count: batch.count)
                return
            }

            switch sendResult {
            case .success:
                statsLock.lock()
                totalSent += batch.count
                statsLock.unlock()
                retryDelay = 0.1
                continue

            case .rehandshake:
                diskQueue.enqueue(batch)
                if options.debug {
                    logger.warning("Server rejected key, re-handshaking")
                }
                KeychainStore.delete()
                stateLock.lock()
                aesKey = nil
                keyID = nil
                stateLock.unlock()
                performHandshakeAsync()
                return

            case .rateLimited(let delay):
                diskQueue.enqueue(batch)
                let backoff = delay ?? min(retryDelay * 2, 60)
                retryDelay = backoff
                rateLimitLock.lock()
                rateLimitPauseUntil = Date().addingTimeInterval(backoff)
                rateLimitLock.unlock()
                recordDrop(.rateLimited, count: batch.count)
                transportQueue.asyncAfter(deadline: .now() + backoff) { [weak self] in
                    self?.sendDiskQueue()
                }
                return

            case .quotaExceeded(let category):
                diskQueue.enqueue(batch)
                if let cat = category {
                    quotaLock.lock()
                    quotaBlocked.insert(cat)
                    quotaLock.unlock()
                }
                recordDrop(.quotaExceeded, count: batch.count)
                return

            case .networkError:
                diskQueue.enqueue(batch)
                recordDrop(.networkError, count: batch.count)
                return
            }
        }
    }

    private enum SendResult {
        case success
        case rehandshake
        case rateLimited(TimeInterval?)
        case quotaExceeded(String?)
        case networkError
    }

    private func sendBatchSync(body: Data, contentType: String, ingestorURL: String) -> SendResult {
        let semaphore = DispatchSemaphore(value: 0)
        var result: SendResult = .networkError

        Task {
            do {
                try await BatchSender.send(
                    body: body,
                    contentType: contentType,
                    ingestorURL: ingestorURL,
                    apiKey: options.apiKey,
                    timeout: options.httpTimeout
                )
                result = .success
            } catch let error as BatchSendError {
                switch error {
                case .authenticationRequired:
                    result = .rehandshake
                case .rateLimited(let retryAfter):
                    result = .rateLimited(retryAfter)
                case .quotaExceeded(let category):
                    result = .quotaExceeded(category)
                case .serverError:
                    result = .networkError
                case .networkError, .invalidURL:
                    result = .networkError
                }
            } catch {
                result = .networkError
            }
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    // MARK: - Handshake

    private func performHandshakeAsync() {
        guard !isHandshaking else { return }
        isHandshaking = true

        Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await Discovery.resolve(options: self.options)
                let handshakeResult = try await Handshake.perform(
                    ingestorURL: url,
                    apiKey: self.options.apiKey,
                    timeout: self.options.httpTimeout
                )

                // Cache in Keychain
                let session = SessionData(
                    aesKeyBase64: AESEncryptor.exportKey(handshakeResult.aesKey).base64EncodedString(),
                    keyID: handshakeResult.keyID,
                    ingestorURL: url,
                    maxBatchSize: handshakeResult.maxBatchSize
                )
                _ = KeychainStore.save(session)

                // Capture values before dispatching
                let aesKey = handshakeResult.aesKey
                let keyID = handshakeResult.keyID
                let maxBatch = handshakeResult.maxBatchSize
                let debugEnabled = self.options.debug

                // Dispatch state update to transport queue to avoid async lock warnings
                self.transportQueue.async { [weak self] in
                    guard let self else { return }

                    self.stateLock.lock()
                    self.aesKey = aesKey
                    self.keyID = keyID
                    self.ingestorURL = url
                    self.maxBatchSize = maxBatch
                    self.stateLock.unlock()

                    self.isHandshaking = false
                    self.retryDelay = 0.1

                    if debugEnabled {
                        self.logger.info("Handshake complete, keyID=\(keyID.prefix(8))...")
                    }

                    self.startFlushTimer()
                    self.flushBuffer()
                }
            } catch {
                self.transportQueue.async { [weak self] in
                    guard let self else { return }
                    self.isHandshaking = false
                    if self.options.debug {
                        self.logger.warning("Handshake failed: \(error.localizedDescription)")
                    }

                    // Retry with exponential backoff
                    let delay = min(self.retryDelay * 2, 60)
                    self.retryDelay = delay
                    self.transportQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                        self?.performHandshakeAsync()
                    }
                }
            }
        }
    }

    // MARK: - Timer

    private func startFlushTimer() {
        flushTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: transportQueue)
        timer.schedule(
            deadline: .now() + options.flushInterval,
            repeating: options.flushInterval
        )
        timer.setEventHandler { [weak self] in
            self?.flushBuffer()
            self?.sendDiskQueue()
        }
        timer.resume()
        flushTimer = timer
    }

    // MARK: - Reachability

    private func startReachability() {
        reachability.start { [weak self] in
            guard let self else { return }
            if self.options.debug {
                self.logger.info("Network connectivity restored")
            }
            self.transportQueue.async {
                self.stateLock.lock()
                let hasKey = self.aesKey != nil
                self.stateLock.unlock()

                if hasKey {
                    self.sendDiskQueue()
                } else {
                    self.performHandshakeAsync()
                }
            }
        }
    }

    // MARK: - Stats helpers

    private func recordDrop(_ reason: DropReason, count: Int) {
        statsLock.lock()
        totalDropped += count
        dropReasons[reason.rawValue, default: 0] += count
        statsLock.unlock()
    }
}

// MARK: - Sampler

/// Probabilistic sampler. Rate 1.0 = send all, 0.0 = drop all.
struct Sampler: Sendable {
    let rate: Double

    init(rate: Double) {
        self.rate = max(0, min(1, rate))
    }

    func shouldSample() -> Bool {
        if rate >= 1.0 { return true }
        if rate <= 0.0 { return false }
        return Double.random(in: 0..<1) < rate
    }
}
