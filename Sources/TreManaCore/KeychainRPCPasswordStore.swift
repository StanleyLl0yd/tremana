import Foundation
import Security

public actor KeychainRPCPasswordStore: RPCPasswordStoring {
    private let service: String

    public init(service: String = "com.sl.tremana.transmission-rpc") {
        self.service = service
    }

    private func query(for id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
    }

    public func read(for id: UUID) async throws -> String? {
        var attributes = query(for: id)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw ProfileStorageError.keychainFailure(status)
        }
        guard let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw ProfileStorageError.invalidKeychainPassword
        }
        return password
    }

    // File-based macOS Keychain entries use per-item ACLs. Explicitly trust
    // only this signed application, using its stable designated requirement,
    // instead of depending on an ACL inherited from an older ad-hoc build.
    private func applicationAccess() throws -> SecAccess {
        var access: SecAccess?
        let status = SecAccessCreate("TreMana Transmission RPC password" as CFString, nil, &access)
        guard status == errSecSuccess else {
            throw ProfileStorageError.keychainFailure(status)
        }
        guard let access else {
            throw ProfileStorageError.keychainFailure(errSecParam)
        }
        return access
    }

    public func upsert(_ password: String, for id: UUID) async throws {
        guard !password.isEmpty else {
            throw ProfileStorageError.passwordRequired
        }
        let query = query(for: id)
        let data = Data(password.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccess as String: try applicationAccess()
        ]

        let updated = SecItemUpdate(
            query as CFDictionary, attributes as CFDictionary
        )
        if updated == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            let inserted = SecItemAdd(insert as CFDictionary, nil)
            guard inserted == errSecSuccess else {
                throw ProfileStorageError.keychainFailure(inserted)
            }
        } else if updated != errSecSuccess {
            throw ProfileStorageError.keychainFailure(updated)
        }
    }

    public func remove(for id: UUID) async throws {
        let status = SecItemDelete(query(for: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProfileStorageError.keychainFailure(status)
        }
    }
}
