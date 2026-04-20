import Foundation

public struct Problem: Codable, Sendable, Equatable {
    public let type: String?
    public let title: String?
    public let status: Int?
    public let detail: String?
    public let instance: String?
    public let code: String?

    public init(type: String? = nil,
                title: String? = nil,
                status: Int? = nil,
                detail: String? = nil,
                instance: String? = nil,
                code: String? = nil) {
        self.type = type
        self.title = title
        self.status = status
        self.detail = detail
        self.instance = instance
        self.code = code
    }
}

public enum APIError: Error, Sendable {
    case transport(underlying: String)
    case http(status: Int, problem: Problem?)
    case decoding(underlying: String)
    /// `HTTP 401 Unauthorized`. `detail` mirrors `Problem.detail` when the
    /// server supplies one (e.g. `"invalid_identity_token:claim_invalid"` for
    /// Sign in with Apple), so UI/logs can surface the concrete reason instead
    /// of a generic "not authorized".
    case unauthorized(detail: String?)
    case ratelimited(retryAfter: TimeInterval?)
    case validation(field: String, reason: String)
    /// `HTTP 402 Payment Required` — the server refused because the caller is on a
    /// tier that forbids the operation. `errorCode` mirrors `Problem.code` (e.g.
    /// `"pro_required"`, `"file_too_large_free"`) so UI can route to a specific
    /// paywall trigger; `problem` carries the full RFC 7807 body when present.
    case paymentRequired(errorCode: String, problem: Problem?)
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .transport(let underlying):
            return "Network error: \(underlying)"
        case .http(let status, let problem):
            if let detail = problem?.detail { return "HTTP \(status): \(detail)" }
            return "HTTP \(status)"
        case .decoding(let underlying):
            return "Could not decode server response: \(underlying)"
        case .unauthorized(let detail):
            if let detail, !detail.isEmpty {
                return "Not authorized: \(detail)"
            }
            return "Device is not authorized."
        case .ratelimited(let retryAfter):
            if let retryAfter { return "Rate limited; try again in \(Int(retryAfter))s." }
            return "Rate limited."
        case .validation(let field, let reason):
            return "Invalid \(field): \(reason)"
        case .paymentRequired(let errorCode, let problem):
            if let detail = problem?.detail { return "Upgrade required: \(detail)" }
            return "Upgrade required (\(errorCode))."
        }
    }
}
