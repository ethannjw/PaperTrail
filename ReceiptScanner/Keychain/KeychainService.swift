// KeychainService.swift
// Type-safe wrapper around Security framework Keychain APIs.
// All API keys and OAuth tokens are stored here — never in UserDefaults.

import Foundation
import Security

enum KeychainError: LocalizedError {
    case unhandledError(status: OSStatus)
    case itemNotFound
    case unexpectedData
    case duplicateItem

    var errorDescription: String? {
        switch self {
        case .unhandledError(let status): return "Keychain error: \(status)"
        case .itemNotFound:               return "Keychain item not found."
        case .unexpectedData:             return "Unexpected keychain data format."
        case .duplicateItem:              return "Keychain item already exists."
        }
    }
}

struct KeychainService {

    // MARK: - Well-known keys
    enum Key: String {
        case openAIAPIKey       = "com.receiptscanner.openai.apikey"
        case geminiAPIKey       = "com.receiptscanner.gemini.apikey"
        case googleAccessToken  = "com.receiptscanner.google.accesstoken"
        case googleRefreshToken = "com.receiptscanner.google.refreshtoken"
        case googleTokenExpiry  = "com.receiptscanner.google.tokenexpiry"
    }

    // MARK: - CRUD

    static func save(_ value: String, for key: Key) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.unexpectedData }

        // Attempt update first
        let updateQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist — insert
            let addQuery: [String: Any] = [
                kSecClass as String:            kSecClassGenericPassword,
                kSecAttrAccount as String:      key.rawValue,
                kSecValueData as String:        data,
                kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlocked
            ]
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandledError(status: addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unhandledError(status: updateStatus)
        }
    }

    static func load(key: Key) throws -> String {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrAccount as String:      key.rawValue,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else { throw KeychainError.itemNotFound }
        guard status == errSecSuccess       else { throw KeychainError.unhandledError(status: status) }
        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return string
    }

    static func delete(key: Key) throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    /// Returns nil if key is absent; throws on real errors.
    static func loadOptional(key: Key) throws -> String? {
        do {
            return try load(key: key)
        } catch KeychainError.itemNotFound {
            return nil
        }
    }
}
