import Foundation
import Network

/// Monitors network connectivity and notifies on changes.
/// Uses NWPathMonitor (available macOS 10.14+, iOS 12+).
final class ReachabilityMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "io.logflux.reachability")
    private var onConnected: (() -> Void)?
    private var wasConnected = true

    func start(onConnected: @escaping () -> Void) {
        self.onConnected = onConnected

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let isConnected = path.status == .satisfied
            if isConnected && !self.wasConnected {
                self.onConnected?()
            }
            self.wasConnected = isConnected
        }

        monitor.start(queue: monitorQueue)
    }

    func stop() {
        monitor.cancel()
        onConnected = nil
    }

    var isConnected: Bool {
        monitor.currentPath.status == .satisfied
    }
}
