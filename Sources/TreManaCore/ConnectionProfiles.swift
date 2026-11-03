import Foundation

public struct ConnectionProfile: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let rpcURL: String
    public let username: String
    public let allowsInsecureHTTP: Bool

    public init(
        id: UUID,
        name: String,
        rpcURL: String,
        username: String,
        allowsInsecureHTTP: Bool
    ) {
        self.id = id
        self.name = name
        self.rpcURL = rpcURL
        self.username = username
        self.allowsInsecureHTTP = allowsInsecureHTTP
    }
}

public enum ProfilePasswordUpdate: Sendable {
    case keep
    case replace(String)
    case remove
}

public enum ProfileStorageError: Error, LocalizedError, Equatable, Sendable {
    case invalidName
    case passwordRequired
    case invalidUsername
    case profileNotFound
    case keychainFailure(Int32)
    case invalidKeychainPassword

    public var errorDescription: String? {
        switch self {
        case .invalidName:
            "Enter a profile name of 1 to 100 characters."
        case .passwordRequired:
            "Enter the password before enabling Keychain storage for a new or changed server."
        case .invalidUsername:
            "The username cannot contain a colon."
        case .profileNotFound:
            "The selected connection profile no longer exists."
        case .keychainFailure(let status):
            "macOS Keychain returned error \(status)."
        case .invalidKeychainPassword:
            "The stored Keychain password could not be decoded."
        }
    }
}

public protocol RPCPasswordStoring: Sendable {
    func read(for id: UUID) async throws -> String?
    func upsert(_ password: String, for id: UUID) async throws
    func remove(for id: UUID) async throws
}

public protocol ConnectionProfileStoring: Sendable {
    func list() async throws -> [ConnectionProfile]
    func password(for id: UUID) async throws -> String?
    func save(_ profile: ConnectionProfile, password: ProfilePasswordUpdate) async throws
    func remove(id: UUID) async throws
}

public actor UserDefaultsProfileStore: ConnectionProfileStoring {
    private static let storageKey = "com.sl.tremana.profiles.v1"
    private let defaults: UserDefaults
    private let passwords: any RPCPasswordStoring

    public init(
        suiteName: String? = nil,
        passwords: any RPCPasswordStoring = KeychainRPCPasswordStore()
    ) {
        if let suiteName {
            guard let isolated = UserDefaults(suiteName: suiteName) else {
                preconditionFailure("Invalid UserDefaults suite name.")
            }
            self.defaults = isolated
        } else {
            self.defaults = .standard
        }
        self.passwords = passwords
    }

    public func list() async throws -> [ConnectionProfile] {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            return []
        }
        return try JSONDecoder().decode([ConnectionProfile].self, from: data)
    }

    public func password(for id: UUID) async throws -> String? {
        guard try await list().contains(where: { $0.id == id }) else {
            throw ProfileStorageError.profileNotFound
        }
        return try await passwords.read(for: id)
    }

    public func save(
        _ profile: ConnectionProfile,
        password update: ProfilePasswordUpdate
    ) async throws {
        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100 else {
            throw ProfileStorageError.invalidName
        }
        guard !profile.username.contains(":") else {
            throw ProfileStorageError.invalidUsername
        }
        guard let url = URL(string: profile.rpcURL) else {
            throw TransmissionRPCError.invalidURL
        }
        _ = try TransmissionConnection(
            url: url, allowInsecureHTTP: profile.allowsInsecureHTTP
        )

        let current = try await list()
        let previous = current.first(where: { $0.id == profile.id })
        if case .keep = update {
            guard let previous,
                  previous.rpcURL == profile.rpcURL,
                  previous.username == profile.username,
                  previous.allowsInsecureHTTP == profile.allowsInsecureHTTP,
                  try await passwords.read(for: profile.id) != nil else {
                throw ProfileStorageError.passwordRequired
            }
        }
        if case .replace(let value) = update, value.isEmpty {
            throw ProfileStorageError.passwordRequired
        }

        let normalized = ConnectionProfile(
            id: profile.id,
            name: name,
            rpcURL: profile.rpcURL,
            username: profile.username,
            allowsInsecureHTTP: profile.allowsInsecureHTTP
        )
        var updated = current.filter { $0.id != normalized.id }
        updated.append(normalized)
        updated.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let data = try JSONEncoder().encode(updated)

        switch update {
        case .keep:
            break
        case .replace(let value):
            try await passwords.upsert(value, for: profile.id)
        case .remove:
            try await passwords.remove(for: profile.id)
        }

        defaults.set(data, forKey: Self.storageKey)
    }

    public func remove(id: UUID) async throws {
        let current = try await list()
        guard current.contains(where: { $0.id == id }) else {
            throw ProfileStorageError.profileNotFound
        }
        let data = try JSONEncoder().encode(current.filter { $0.id != id })
        try await passwords.remove(for: id)
        defaults.set(data, forKey: Self.storageKey)
    }
}
