import Foundation

/// Wire format models for the LogFlux ingestor.

// MARK: - Handshake Models

struct HandshakeInitRequest: Codable {
    let api_key: String
}

struct HandshakeInitResponse: Codable {
    let status: String
    let data: HandshakeInitData?

    struct HandshakeInitData: Codable {
        let public_key: String
        let max_batch_size: Int?
        let max_payload_size: Int64?
        let max_request_size: Int64?
    }
}

struct HandshakeCompleteRequest: Codable {
    let api_key: String
    let encrypted_secret: String
}

struct HandshakeCompleteResponse: Codable {
    let status: String
    let data: HandshakeCompleteData?

    struct HandshakeCompleteData: Codable {
        let status: String?
        let key_id: String?
    }
}

// MARK: - Discovery Models

struct DiscoveryResponse: Codable {
    let status: String
    let data: DiscoveryData?

    struct DiscoveryData: Codable {
        let ingest_url: String?
        let handshake_url: String?
        let health_url: String?
        let base_url: String?
    }
}

// MARK: - Error Response

struct ErrorResponse: Codable {
    let status: String
    let error: ErrorDetail?

    struct ErrorDetail: Codable {
        let code: String?
        let message: String?
    }
}
