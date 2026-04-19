import Foundation
import Security

public protocol KeychainStoring: Sendable {
    func read(_ key: String) async throws -> Data?
    func write(_ data: Data, for key: String) async throws
    func delete(_ key: String) async throws
}

public enum KeychainError: Error, Sendable, LocalizedError {
    case unexpectedStatus(OSStatus)
    case dataEncoding

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            let name = Self.describe(status: status)
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
            return "Keychain failed: \(name) (\(status)) — \(message)"
        case .dataEncoding:
            return "Keychain data could not be encoded"
        }
    }

    // WHY: surfacing the OSStatus symbol in logs makes extension-context failures
    // (errSecMissingEntitlement, errSecInteractionNotAllowed) debuggable.
    private static func describe(status: OSStatus) -> String {
        switch status {
        case errSecSuccess:             return "errSecSuccess"
        case errSecItemNotFound:        return "errSecItemNotFound"
        case errSecDuplicateItem:       return "errSecDuplicateItem"
        case errSecInteractionNotAllowed: return "errSecInteractionNotAllowed"
        case errSecAuthFailed:          return "errSecAuthFailed"
        case errSecParam:               return "errSecParam"
        case -34018:                    return "errSecMissingEntitlement"
        case -25243:                    return "errSecNoAccessForItem"
        default:                        return "osstatus=\(status)"
        }
    }
}

public final class KeychainStore: KeychainStoring, @unchecked Sendable {
    private let service: String
    private let accessGroup: String?

    public init(service: String, accessGroup: String?) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func read(_ key: String) async throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func write(_ data: Data, for key: String) async throws {
        let query = baseQuery(for: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insertQuery = query
            for (k, v) in attributes { insertQuery[k] = v }
            let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    public func delete(_ key: String) async throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if let accessGroup, !accessGroup.isEmpty {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
