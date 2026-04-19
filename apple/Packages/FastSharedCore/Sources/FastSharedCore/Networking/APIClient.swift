import Foundation
import OSLog

public protocol APIClientProtocol: Sendable {
    func registerDevice(platform: String, appVersion: String) async throws -> DeviceToken
    func requestUpload(_ request: PresignRequest) async throws -> PresignResponse
    func completeUpload(uploadId: String, request: CompleteRequest) async throws -> CompleteResponse
    func failUpload(uploadId: String, errorCode: String, message: String?) async throws
    func fetchHistory(cursor: String?, limit: Int) async throws -> HistoryPage
    func deleteAsset(_ id: UUID) async throws
    func revokeLink(token: String) async throws -> RevokeResponse
    func shortURL(forToken token: String) -> URL
    func verifyIAP(signedTransactionJWS: String) async throws -> IAPVerifyResponse
    func fetchMe() async throws -> MeResponse
    func fetchPricingFlags() async throws -> PricingFlags
}

public final class APIClient: APIClientProtocol, @unchecked Sendable {
    private let session: URLSession
    private let signer: RequestSigner
    private let tokenStore: DeviceTokenStore
    private let baseURL: URL
    private let shortLinkHost: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let log = Logger(subsystem: Log.subsystem, category: "network")

    public init(tokenStore: DeviceTokenStore,
                session: URLSession = .shared,
                baseURL: URL? = nil,
                shortLinkHost: URL? = nil,
                signer: RequestSigner = RequestSigner()) {
        self.tokenStore = tokenStore
        self.session = session
        self.baseURL = baseURL ?? AppGroupConfig.apiBaseURL
        self.shortLinkHost = shortLinkHost ?? AppGroupConfig.shortLinkHost
        self.signer = signer

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = APIClient.iso8601Fractional.date(from: raw) { return date }
            if let date = APIClient.iso8601Plain.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container,
                                                   debugDescription: "Unrecognized ISO 8601 date: \(raw)")
        }
        self.decoder = decoder
    }

    // WHY: server timestamps vary between whole-second ISO 8601 and fractional-second variants depending
    // on upstream library; support both without losing precision when fractional seconds are present.
    private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public func registerDevice(platform: String, appVersion: String) async throws -> DeviceToken {
        let body = RegisterDeviceRequest(platform: platform, appVersion: appVersion)
        let response: RegisterDeviceResponse = try await perform(endpoint: .registerDevice, body: body, requiresAuth: false)
        return DeviceToken(deviceId: response.deviceId, token: response.deviceToken)
    }

    public func requestUpload(_ request: PresignRequest) async throws -> PresignResponse {
        try await perform(endpoint: .requestUpload, body: request)
    }

    public func completeUpload(uploadId: String, request: CompleteRequest) async throws -> CompleteResponse {
        try await perform(endpoint: .completeUpload(uploadId: uploadId), body: request)
    }

    public func failUpload(uploadId: String, errorCode: String, message: String?) async throws {
        let body = FailRequest(errorCode: errorCode, message: message)
        try await performVoid(endpoint: .failUpload(uploadId: uploadId), body: body)
    }

    public func fetchHistory(cursor: String?, limit: Int) async throws -> HistoryPage {
        var components = URLComponents(url: baseURL.appendingPathComponent(APIEndpoint.fetchHistory.path), resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        components?.queryItems = items
        guard let url = components?.url else { throw APIError.transport(underlying: "bad URL") }
        var request = URLRequest(url: url)
        request.httpMethod = APIEndpoint.fetchHistory.method.rawValue
        try await attachAuth(&request)
        return try await send(request)
    }

    public func deleteAsset(_ id: UUID) async throws {
        let endpoint = APIEndpoint.deleteAsset(id: id)
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint.path))
        request.httpMethod = endpoint.method.rawValue
        try await attachAuth(&request)
        let (_, httpResponse) = try await dataTask(request)
        try validate(httpResponse, data: Data())
    }

    public func revokeLink(token: String) async throws -> RevokeResponse {
        let endpoint = APIEndpoint.revokeLink(token: token)
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint.path))
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        try await attachAuth(&request)
        return try await send(request)
    }

    public func shortURL(forToken token: String) -> URL {
        shortLinkHost.appendingPathComponent("s").appendingPathComponent(token)
    }

    public func verifyIAP(signedTransactionJWS: String) async throws -> IAPVerifyResponse {
        let body = IAPVerifyRequest(signedTransaction: signedTransactionJWS)
        return try await perform(endpoint: .iapVerify, body: body)
    }

    public func fetchMe() async throws -> MeResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent(APIEndpoint.me.path))
        request.httpMethod = APIEndpoint.me.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        try await attachAuth(&request)
        return try await send(request)
    }

    public func fetchPricingFlags() async throws -> PricingFlags {
        var request = URLRequest(url: baseURL.appendingPathComponent(APIEndpoint.pricingFlags.path))
        request.httpMethod = APIEndpoint.pricingFlags.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        try await attachAuth(&request)
        return try await send(request)
    }

    // MARK: - Internals

    private func perform<Body: Encodable, Response: Decodable>(endpoint: APIEndpoint,
                                                               body: Body,
                                                               requiresAuth: Bool = true) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint.path))
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)
        if requiresAuth { try await attachAuth(&request) } else { signer.sign(&request, token: nil) }
        return try await send(request)
    }

    private func performVoid<Body: Encodable>(endpoint: APIEndpoint, body: Body) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint.path))
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        try await attachAuth(&request)
        let (data, httpResponse) = try await dataTask(request)
        try validate(httpResponse, data: data)
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, httpResponse) = try await dataTask(request)
        try validate(httpResponse, data: data)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            log.error("decode failed: \(error.localizedDescription, privacy: .public)")
            throw APIError.decoding(underlying: error.localizedDescription)
        }
    }

    private func dataTask(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport(underlying: "non-HTTP response")
            }
            return (data, http)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(underlying: error.localizedDescription)
        }
    }

    private func validate(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw APIError.unauthorized
        case 402:
            // WHY: 402 is surfaced as a dedicated typed error so UI callers can route
            // to the paywall coordinator instead of parsing a generic `.http` payload.
            let problem = try? decoder.decode(Problem.self, from: data)
            throw APIError.paymentRequired(errorCode: problem?.code ?? "payment_required",
                                           problem: problem)
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw APIError.ratelimited(retryAfter: retryAfter)
        default:
            let problem = try? decoder.decode(Problem.self, from: data)
            throw APIError.http(status: response.statusCode, problem: problem)
        }
    }

    private func attachAuth(_ request: inout URLRequest) async throws {
        let token = try await tokenStore.load()?.token
        signer.sign(&request, token: token)
    }
}
