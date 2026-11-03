import Foundation
import Testing
@testable import TreManaCore

@Suite("Connection profile persistence")
struct ConnectionProfileTests {
    @Test func passwordsAreNeverSerializedInUserDefaults() async throws {
        let suiteName = "TreMana.Profiles.Test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let passwords = MemoryPasswords()
        let store = UserDefaultsProfileStore(defaults: defaults, passwords: passwords)
        let profile = fixtureProfile()
        let secret = "Only-In-Keychain-Secret-934"

        try await store.save(profile, password: .replace(secret))
        let listed = try await store.list()
        #expect(listed == [profile])
        let stored = try await store.password(for: profile.id)
        #expect(stored == secret)

        let bytes = try #require(defaults.data(forKey: "com.sl.tremana.profiles.v1"))
        let json = try #require(String(data: bytes, encoding: .utf8))
        #expect(!json.contains(secret))
        #expect(json.contains(profile.name))
        #expect(json.contains(profile.rpcURL))

        try await store.remove(id: profile.id)
        #expect(try await store.list().isEmpty)
        #expect(await passwords.read(for: profile.id) == nil)
    }

    @Test func cannotReuseSavedPasswordForDifferentServer() async throws {
        let suiteName = "TreMana.Profiles.Test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let passwords = MemoryPasswords()
        let store = UserDefaultsProfileStore(defaults: defaults, passwords: passwords)
        let original = fixtureProfile()
        try await store.save(original, password: .replace("secure-value"))
        let changed = ConnectionProfile(
            id: original.id, name: original.name,
            rpcURL: "https://other.example/transmission/rpc",
            username: "admin", allowsInsecureHTTP: false
        )

        do {
            try await store.save(changed, password: .keep)
            Issue.record("Password reuse must require the same authentication endpoint")
        } catch let error as ProfileStorageError {
            #expect(error == .passwordRequired)
        }
        #expect(try await store.list() == [original])
        #expect(try await store.password(for: original.id) == "secure-value")
    }

    @Test func credentialsEmbeddedInURLAreRefused() async throws {
        let suiteName = "TreMana.Profiles.Test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsProfileStore(
            defaults: defaults, passwords: MemoryPasswords()
        )
        let profile = ConnectionProfile(
            id: UUID(), name: "Unsafe",
            rpcURL: "https://admin:password@router.example/transmission/rpc",
            username: "admin", allowsInsecureHTTP: false
        )
        do {
            try await store.save(profile, password: .remove)
            Issue.record("Credentials in URL must be rejected")
        } catch let error as TransmissionRPCError {
            #expect(error == .invalidURL)
        }
    }

    @Test func corruptedProfileDataFailsRatherThanSilentlyOverwriting() async throws {
        let suiteName = "TreMana.Profiles.Test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("invalid json".utf8), forKey: "com.sl.tremana.profiles.v1")
        let store = UserDefaultsProfileStore(
            defaults: defaults, passwords: MemoryPasswords()
        )
        do {
            _ = try await store.list()
            Issue.record("Expected explicit decoding failure")
        } catch {}
        do {
            try await store.save(fixtureProfile(), password: .remove)
            Issue.record("Corrupted data must not be replaced silently")
        } catch {}
        #expect(
            defaults.data(forKey: "com.sl.tremana.profiles.v1")
                == Data("invalid json".utf8)
        )
    }
}

func fixtureProfile(id: UUID = UUID()) -> ConnectionProfile {
    ConnectionProfile(
        id: id, name: "Home Keenetic",
        rpcURL: "https://router.example/transmission/rpc",
        username: "admin", allowsInsecureHTTP: false
    )
}

actor MemoryPasswords: RPCPasswordStoring {
    private var values: [UUID: String] = [:]

    func read(for id: UUID) async throws -> String? {
        values[id]
    }

    func upsert(_ password: String, for id: UUID) async throws {
        values[id] = password
    }

    func remove(for id: UUID) async throws {
        values[id] = nil
    }
}
