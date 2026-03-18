# LogFlux Swift SDK

The official Swift SDK for [LogFlux.io](https://logflux.io) -- secure, zero-knowledge log ingestion with end-to-end encryption for iOS and macOS apps.

## Features

- **End-to-end encryption** -- AES-256-GCM with RSA key exchange. Server never sees plaintext.
- **7 entry types** -- Log, Metric, Trace, Event, Audit, Telemetry, TelemetryManaged
- **Multipart binary transport** -- 33% less overhead than JSON + base64
- **Async by default** -- Non-blocking queue with background workers
- **Disk persistence** -- Entries survive app termination and network outages
- **Automatic breadcrumbs** -- Trail of recent events attached to error captures
- **Distributed tracing** -- Span helpers with context propagation
- **Keychain storage** -- AES keys stored securely in the iOS/macOS Keychain
- **Failsafe** -- SDK errors never crash your application
- **Zero external dependencies** -- Apple frameworks only

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/logflux-io/logflux-swift-sdk.git", from: "3.0.0")
]
```

Or in Xcode: File > Add Package Dependencies > enter the repository URL.

## Quick Start

```swift
import LogFlux

// Initialize once at app startup
try LogFlux.initialize(options: Options(apiKey: "eu-lf_your_api_key") {
    $0.source = "my-ios-app"
    $0.environment = "production"
    $0.release = "1.2.3"
})

// Send logs
LogFlux.info("app launched")
LogFlux.warn("low battery")

// Flush before app terminates
LogFlux.flush(timeout: 2.0)
```

## Entry Types

### Log (Type 1)

Standard application logs with 8 severity levels.

```swift
LogFlux.debug("cache miss for key users:123")
LogFlux.info("request processed")
LogFlux.warn("deprecated API called")
LogFlux.error("network request failed")
LogFlux.critical("out of memory")

// With attributes
LogFlux.log(level: .error, "query timeout", attributes: [
    "db.host": "primary.db.internal",
    "duration_ms": "5023",
])
```

### Metric (Type 2)

Counters, gauges, and distributions.

```swift
LogFlux.counter("http.requests.total", value: 1, attributes: [
    "method": "GET",
    "status": "200",
])

LogFlux.gauge("system.memory.used", value: 85.2, attributes: [
    "host": "iphone-14",
])
```

### Event (Type 4)

Discrete application events.

```swift
LogFlux.event("user.signup", attributes: [
    "user_id": "usr_987",
    "plan": "starter",
])
```

### Audit (Type 5)

Immutable audit trail with Object Lock storage (365-day retention).

```swift
LogFlux.audit("record.deleted", actor: "usr_456", resource: "invoice", resourceID: "inv_789", attributes: [
    "reason": "customer_request",
])
```

### Trace (Type 3)

Distributed tracing with span helpers.

```swift
let span = LogFlux.startSpan("http.request", "GET /api/users")
defer { span.end() }

let dbSpan = span.startChild("db.query", "SELECT * FROM users")
dbSpan.end()
```

### Telemetry (Types 6 and 7)

Device and sensor data. Type 6 is end-to-end encrypted, type 7 is server-side encrypted.

## Error Capture

Capture Swift errors with automatic breadcrumb trail.

```swift
do {
    try database.query(sql)
} catch {
    LogFlux.captureError(error)

    // With extra context
    LogFlux.captureError(error, attributes: [
        "sql": sql,
        "db.host": "primary",
    ])
}
```

## Breadcrumbs

Breadcrumbs record a trail of events leading up to an error. They are automatically added for log and event calls, and attached to `captureError`.

```swift
LogFlux.info("loading config")          // auto breadcrumb
LogFlux.event("user.login")             // auto breadcrumb

LogFlux.addBreadcrumb("http", "GET /api/users", data: [
    "status": "200",
])

LogFlux.captureError(error)  // includes breadcrumb trail
```

## Scopes

Per-request context isolation. Attributes set on a scope are merged into every entry.

```swift
LogFlux.withScope { scope in
    scope.setUser("usr_456")
    scope.setRequest("GET", path: "/api/users", requestID: "req_abc123")
    scope.setAttribute("tenant", value: "acme-corp")

    scope.info("processing request")

    if let error = error {
        scope.captureError(error)
    }
}
```

## Trace Context Propagation

Propagate trace context across network requests.

```swift
// Inject into outgoing URLRequest
let span = LogFlux.startSpan("http.client", "GET /api")
var request = URLRequest(url: url)
request.setValue(span.traceHeader, forHTTPHeaderField: "X-LogFlux-Trace")

// Continue from incoming headers
let span = LogFlux.continueFromRequest(headers, operation: "http.server", description: "GET /api")
defer { span.end() }
```

## Configuration

### Options

```swift
var opts = Options(apiKey: "eu-lf_your_api_key")
opts.source = "my-ios-app"
opts.environment = "production"
opts.release = "1.2.3"
opts.queueSize = 1000          // in-memory buffer
opts.batchSize = 100           // entries per request
opts.flushInterval = 5         // seconds
opts.workerCount = 2           // background threads
opts.maxRetries = 3
opts.sampleRate = 1.0          // 0.0-1.0
opts.maxBreadcrumbs = 100
opts.failsafe = true           // never crash host app
opts.enableCompression = true  // gzip before encryption
```

### Environment Variables

```swift
try LogFlux.initFromEnvironment(node: "iphone-14")
```

Reads `LOGFLUX_API_KEY`, `LOGFLUX_ENVIRONMENT`, `LOGFLUX_NODE`, `LOGFLUX_QUEUE_SIZE`, `LOGFLUX_BATCH_SIZE`, `LOGFLUX_WORKER_COUNT`, etc.

## BeforeSend Hooks

Filter or modify entries before they are sent. Return `nil` to drop.

```swift
opts.beforeSendLog = { log in
    if log.level == LogLevel.debug.rawValue {
        return nil  // drop debug logs
    }
    return log
}

opts.beforeSendAudit = { audit in
    var a = audit
    a.attributes?.removeValue(forKey: "ip")  // scrub PII
    return a
}
```

## Sampling

```swift
opts.sampleRate = 0.1  // send 10% of entries
```

Audit entries (type 5) are never sampled.

## Disk Persistence

Unlike server-side SDKs, the Swift SDK persists entries to disk before sending. This ensures data survives:
- App suspension/termination by iOS
- Network connectivity loss
- App crashes

Entries are stored in `~/Library/Caches/io.logflux.queue/` as individual files with FIFO ordering and automatic eviction when the queue exceeds `maxQueueSize`.

## Security

- **Zero-knowledge**: All payloads encrypted client-side with AES-256-GCM
- **RSA key exchange**: AES keys negotiated via RSA-2048 OAEP handshake
- **Keychain storage**: AES keys stored in iOS/macOS Keychain (whenUnlockedThisDeviceOnly)
- **Key zeroing**: AES keys cleared from memory on `close()`
- **Bounded reads**: All HTTP responses size-limited (1MB)
- **Failsafe**: SDK errors never crash the host application

## Requirements

- Swift 5.9 or later
- macOS 13+ / iOS 16+ / tvOS 16+ / watchOS 9+
- LogFlux account with API key

## No External Dependencies

Uses only Apple frameworks: CryptoKit, Security, Foundation, Network, Compression, os.log.

## License

[Business Source License 1.1](LICENSE) -- free for all use except competing commercial logging services. Converts to Apache 2.0 on 2029-03-16.

## Support

- **Issues**: [GitHub Issues](https://github.com/logflux-io/logflux-swift-sdk/issues)
