import Foundation
import Security

enum KeychainError: LocalizedError {
    case itemNotFound
    case duplicateItem
    case invalidData
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .itemNotFound: "Keychain 中未找到该条目"
        case .duplicateItem: "Keychain 中存在重复条目"
        case .invalidData: "Keychain 数据格式无效"
        case .unexpectedStatus(let status): "Keychain 操作失败，错误码: \(status)"
        }
    }
}

struct KeychainHelper {
    private static let service = "com.chaogeek.ShellDeck"

    static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try? delete(key: key)

        var query = [String: Any]()
        query[String(kSecClass)] = kSecClassGenericPassword
        query[String(kSecAttrService)] = service
        query[String(kSecAttrAccount)] = key
        query[String(kSecValueData)] = data
        query[String(kSecAttrAccessible)] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func read(key: String) throws -> String {
        var query = [String: Any]()
        query[String(kSecClass)] = kSecClassGenericPassword
        query[String(kSecAttrService)] = service
        query[String(kSecAttrAccount)] = key
        query[String(kSecReturnData)] = true
        query[String(kSecMatchLimit)] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            throw KeychainError.itemNotFound
        }
        guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return string
    }

    static func delete(key: String) {
        var query = [String: Any]()
        query[String(kSecClass)] = kSecClassGenericPassword
        query[String(kSecAttrService)] = service
        query[String(kSecAttrAccount)] = key

        SecItemDelete(query as CFDictionary)
    }
}
