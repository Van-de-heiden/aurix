import Foundation
import Security

enum Keychain {
    private static let service = "ch.aurix.personal.openai"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "api-key"]
    }
    static func read() -> String? {
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ key: String) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-"), key.count >= 20, !key.contains(where: \.isWhitespace) else { throw KeyError.invalid }
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let result = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard result == errSecSuccess else { throw KeyError.storage }
        } else if status != errSecSuccess { throw KeyError.storage }
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyError.storage }
    }
    enum KeyError: LocalizedError {
        case invalid, storage
        var errorDescription: String? { self == .invalid ? "Bitte füge einen vollständigen OpenAI-API-Schlüssel ein." : "Der Schlüssel konnte nicht im iPhone-Schlüsselbund gespeichert werden." }
    }
}
