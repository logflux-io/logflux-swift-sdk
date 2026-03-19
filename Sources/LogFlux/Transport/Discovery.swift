import Foundation

enum DiscoveryError: Error {
    case noEndpointConfigured
    case requestFailed(Error)
    case invalidResponse
    case noIngestURL
}

/// Resolves the ingestor URL from options.
///
/// Priority: customEndpointURL > zone > API key region > discoveryURL
enum Discovery {

    private static let ingestorURLTemplate = "https://api.ingest.%@.logflux.io"

    /// Resolve the ingestor endpoint from options.
    static func resolve(options: Options) async throws -> String {
        // 1. Direct URL - use as-is
        if let customURL = options.customEndpointURL, !customURL.isEmpty {
            return customURL
        }

        // 2. Zone - construct URL directly, no network call
        if let zone = options.zone, !zone.isEmpty {
            return String(format: ingestorURLTemplate, zone)
        }

        // 3. Extract region from API key
        if let region = options.extractRegion() {
            return String(format: ingestorURLTemplate, region)
        }

        throw DiscoveryError.noEndpointConfigured
    }
}
