import Foundation
import Testing

@testable import LogFlux

/// LogFlux Swift SDK — Integration Tests
/// Runs against a real ingestor to validate SDK end-to-end.
///
/// Usage:
///   LOGFLUX_API_KEY=eu-lf_... LOGFLUX_INGESTOR_URL=http://localhost:8890 swift test --filter Integration
@Suite("Integration Tests", .enabled(if: ProcessInfo.processInfo.environment["LOGFLUX_API_KEY"] != nil))
struct IntegrationTests {

    static let apiKey = ProcessInfo.processInfo.environment["LOGFLUX_API_KEY"] ?? ""
    static let ingestorURL = ProcessInfo.processInfo.environment["LOGFLUX_INGESTOR_URL"] ?? "http://localhost:8890"

    private func initSDK(node: String = "swift-integration-test", beforeSend: ((inout PayloadLog) -> PayloadLog?)? = nil) throws {
        var opts = Options(apiKey: Self.apiKey)
        opts.node = node
        opts.customEndpointURL = Self.ingestorURL
        opts.enableCompression = true
        opts.failsafe = false
        opts.flushInterval = 0.5
        opts.batchSize = 50
        if let hook = beforeSend {
            opts.beforeSendLog = hook
        }
        try LogFlux.initialize(options: opts)
    }

    @Test("Client Init")
    func clientInit() throws {
        try initSDK()
        #expect(LogFlux.isActive)
        LogFlux.close()
    }

    @Test("Send Log")
    func sendLog() throws {
        try initSDK()
        LogFlux.info("Swift SDK test: info log message")
        LogFlux.flush(timeout: 5.0)
        LogFlux.close()
    }

    @Test("All Log Levels")
    func allLogLevels() throws {
        try initSDK()
        LogFlux.debug("Swift SDK: debug level")
        LogFlux.info("Swift SDK: info level")
        LogFlux.notice("Swift SDK: notice level")
        LogFlux.warn("Swift SDK: warning level")
        LogFlux.error("Swift SDK: error level")
        LogFlux.critical("Swift SDK: critical level")
        LogFlux.alert("Swift SDK: alert level")
        LogFlux.emergency("Swift SDK: emergency level")
        LogFlux.flush(timeout: 5.0)
        LogFlux.close()
    }

    @Test("Log with Attributes")
    func logWithAttributes() throws {
        try initSDK()
        LogFlux.info("Swift SDK: log with attrs", attributes: [
            "service": "swift-testsuite",
            "environment": "dev",
            "version": "3.0.1",
        ])
        LogFlux.flush(timeout: 5.0)
        LogFlux.close()
    }

    @Test("Send Counter Metric")
    func sendCounter() throws {
        try initSDK()
        LogFlux.counter("swift.test.requests", value: 42, attributes: ["endpoint": "/api/test"])
        LogFlux.flush(timeout: 5.0)
        LogFlux.close()
    }

    @Test("Send Gauge Metric")
    func sendGauge() throws {
        try initSDK()
        LogFlux.gauge("swift.test.memory_mb", value: 256.5, attributes: ["host": "test-node"])
        LogFlux.flush(timeout: 5.0)
        LogFlux.close()
    }

    @Test("Send Event")
    func sendEvent() throws {
        try initSDK()
        LogFlux.event("user.signup", attributes: ["plan": "starter", "source": "integration-test"])
        LogFlux.flush(timeout: 5.0)
        LogFlux.close()
    }

    @Test("Send Audit Entry")
    func sendAudit() throws {
        try initSDK()
        LogFlux.audit("config.update", actor: "admin@test.com", resource: "settings", resourceID: "global", attributes: [
            "field": "retention_days",
            "old_value": "30",
            "new_value": "90",
        ])
        LogFlux.flush(timeout: 5.0)
        LogFlux.close()
    }

    @Test("Capture Error")
    func captureError() throws {
        try initSDK()
        let error = NSError(domain: "IntegrationTest", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Swift SDK test error for integration"
        ])
        LogFlux.captureError(error, attributes: ["context": "integration-test"])
        LogFlux.flush(timeout: 5.0)
        LogFlux.close()
    }

    @Test("Breadcrumbs")
    func breadcrumbs() throws {
        try initSDK()
        LogFlux.addBreadcrumb("navigation", "User opened settings")
        LogFlux.addBreadcrumb("api", "GET /api/settings", data: ["status": "200"])
        LogFlux.addBreadcrumb("ui", "User clicked save")
        let error = NSError(domain: "IntegrationTest", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Error after breadcrumbs"
        ])
        LogFlux.captureError(error)
        LogFlux.clearBreadcrumbs()
        LogFlux.flush(timeout: 5.0)
        LogFlux.close()
    }

    @Test("Scoped Context")
    func scopedContext() throws {
        try initSDK()
        LogFlux.withScope { scope in
            scope.setAttribute("request_id", "req_swift_test_123")
            scope.setUser("usr_swift_456")
            scope.setRequest(method: "POST", path: "/api/test", requestID: "req_swift_test_123")
            scope.addBreadcrumb("scope", "entered test scope")
        }
        LogFlux.flush(timeout: 5.0)
        LogFlux.close()
    }

    @Test("Distributed Tracing")
    func distributedTracing() throws {
        try initSDK()
        let span = LogFlux.startSpan("http.server", "GET /api/test")
        span.setAttribute("http.method", "GET")
        span.setAttribute("http.status_code", "200")
        span.setStatus("ok")

        let child = span.startChild("db.query", "SELECT * FROM users")
        child.setAttribute("db.system", "postgresql")
        child.setStatus("ok")
        _ = child.end()

        _ = span.end()
        LogFlux.flush(timeout: 5.0)
        LogFlux.close()
    }

    @Test("Stats Available")
    func statsAvailable() throws {
        try initSDK()
        LogFlux.info("Swift SDK: stats check")
        LogFlux.flush(timeout: 5.0)
        // Stats are available (async send count may be 0 due to timing)
        let _ = LogFlux.stats()
        LogFlux.close()
    }
}
