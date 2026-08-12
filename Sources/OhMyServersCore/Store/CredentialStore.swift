import Foundation
import Security

public enum CredentialKind: String, Sendable {
    case password
    case keyPassphrase
}

public struct CredentialStore: Sendable {
    public var service: String

    public init(service: String = "app.ohmyservers.credentials") {
        self.service = service
    }

    public func account(for serverID: UUID, kind: CredentialKind) -> String {
        "server.\(serverID.uuidString).\(kind.rawValue)"
    }

    public func save(serverID: UUID, kind: CredentialKind, secret: String) throws {
        let account = account(for: serverID, kind: kind)
        let data = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialStoreError.keychain(status)
        }
    }

    public func load(serverID: UUID, kind: CredentialKind) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: serverID, kind: kind),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CredentialStoreError.keychain(status)
        }
        return String(data: data, encoding: .utf8)
    }

    public func delete(serverID: UUID, kind: CredentialKind) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: serverID, kind: kind)
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }

    public func deleteAll(for serverID: UUID) throws {
        try delete(serverID: serverID, kind: .password)
        try delete(serverID: serverID, kind: .keyPassphrase)
    }
}

public enum CredentialStoreError: Error, Sendable {
    case keychain(OSStatus)
}
