import Foundation
import Testing
@testable import TreManaCore

@Suite("Connection lifecycle")
struct TreManaModelTests {
    @Test @MainActor func rememberedConnectionRestoresAfterAppRestart() async throws {
        let suiteName = "TreMana.Remember.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let passwords = MemoryPasswords()
        let profiles = UserDefaultsProfileStore(
            suiteName: suiteName, passwords: passwords
        )
        let remote = ControlledRPC(hold: .none, torrents: [])
        let original = TreManaModel(
            makeClient: { _ in remote }, profileStore: profiles
        )
        original.rpcURL = "https://home.example/transmission/rpc"
        original.username = "transmission"
        original.password = "secret-value"
        original.rememberPassword = true

        await original.connect()
        #expect(original.isConnected)
        #expect(original.profileErrorMessage == nil)
        #expect(original.noticeMessage == "Connection remembered securely")
        #expect(original.password.isEmpty)
        let saved = try await profiles.list()
        let first = try #require(saved.first)
        #expect(saved.count == 1)
        #expect(first.name == "home.example")
        #expect(first.username == "transmission")
        #expect(try await profiles.password(for: first.id) == "secret-value")
        #expect(await profiles.preferredProfileID() == first.id)

        let capture = ConnectionCapture()
        let relaunched = TreManaModel(
            makeClient: { connection in
                capture.connection = connection
                return remote
            },
            profileStore: profiles
        )
        await relaunched.reloadProfiles()
        #expect(relaunched.selectedProfileID == first.id)
        #expect(relaunched.profileName == "home.example")
        #expect(relaunched.rpcURL == first.rpcURL)
        #expect(relaunched.username == "transmission")
        #expect(relaunched.rememberPassword)
        #expect(relaunched.savedPasswordAvailable)
        #expect(relaunched.password.isEmpty)

        await relaunched.connect()
        #expect(relaunched.isConnected)
        #expect(capture.connection?.credentials?.password == "secret-value")
        #expect(try await profiles.list().count == 1)
    }

    @Test @MainActor func noOptInNeverStoresCredentials() async throws {
        let suiteName = "TreMana.OptOut.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let passwords = MemoryPasswords()
        let store = UserDefaultsProfileStore(
            suiteName: suiteName, passwords: passwords
        )
        let remote = ControlledRPC(hold: .none, torrents: [])
        let model = TreManaModel(
            makeClient: { _ in remote }, profileStore: store
        )
        model.rpcURL = "https://private.example/transmission/rpc"
        model.username = "admin"
        model.password = "never-persist"
        #expect(!model.rememberPassword)

        await model.connect()
        #expect(model.isConnected)
        #expect(model.password.isEmpty)
        #expect(try await store.list().isEmpty)
    }

    @Test @MainActor func keychainSaveFailureDoesNotBreakConnection() async throws {
        let suiteName = "TreMana.KeychainFailure.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsProfileStore(
            suiteName: suiteName, passwords: DeniedPasswords()
        )
        let remote = ControlledRPC(hold: .none, torrents: [])
        let model = TreManaModel(
            makeClient: { _ in remote }, profileStore: store
        )
        model.rpcURL = "https://router.example/transmission/rpc"
        model.username = "admin"
        model.password = "secret"
        model.rememberPassword = true

        await model.connect()
        #expect(model.isConnected)
        #expect(model.errorMessage == nil)
        #expect(model.profileErrorMessage?.contains("34018") == true)
        #expect(try await store.list().isEmpty)
        #expect(model.password.isEmpty)
    }

    @Test @MainActor func keychainPasswordCannotLeakToEditedServer() async throws {
        let suiteName = "TreMana.Profiles.Model.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let profiles = UserDefaultsProfileStore(
            suiteName: suiteName, passwords: MemoryPasswords()
        )
        let profile = fixtureProfile()
        try await profiles.save(profile, password: .replace("secret-password"))

        let remote = ControlledRPC(hold: .none, torrents: [])
        let capture = ConnectionCapture()
        let model = TreManaModel(
            makeClient: { connection in
                capture.connection = connection
                return remote
            },
            profileStore: profiles
        )

        await model.reloadProfiles()
        await model.chooseProfile(profile.id)
        #expect(model.rememberPassword)
        #expect(model.password.isEmpty)

        await model.connect()
        #expect(capture.connection?.credentials?.password == "secret-password")
        model.disconnect()

        model.rpcURL = "https://untrusted.example/transmission/rpc"
        #expect(!model.canReuseSavedPassword)
        await model.connect()
        #expect(capture.connection?.url.host == "untrusted.example")
        #expect(capture.connection?.credentials?.password == "")
    }

    @Test @MainActor func disconnectWhileNegotiatingDoesNotReconnect() async {
        let remote = ControlledRPC(hold: .session, torrents: [fixtureTorrent(1)])
        let model = TreManaModel(makeClient: { _ in remote })
        model.rpcURL = "https://router.example/transmission/rpc"
        model.username = "admin"
        model.password = "secret"

        let task = Task { await model.connect() }
        await remote.waitForHeldCall()
        #expect(model.isBusy)

        model.disconnect()
        #expect(!model.isConnected)
        #expect(model.password.isEmpty)
        #expect(!model.isBusy)

        await remote.resumeHeldCall()
        await task.value
        #expect(!model.isConnected)
        #expect(model.torrents.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(!model.isBusy)
    }

    @Test @MainActor func disconnectWhileLoadingInitialTorrentsDoesNotReconnect() async {
        let remote = ControlledRPC(hold: .initialTorrents, torrents: [fixtureTorrent(1)])
        let model = TreManaModel(makeClient: { _ in remote })
        model.rpcURL = "https://router.example/transmission/rpc"

        let task = Task { await model.connect() }
        await remote.waitForHeldCall()
        model.disconnect()
        await remote.resumeHeldCall()
        await task.value

        #expect(model.server == nil)
        #expect(model.torrents.isEmpty)
        #expect(!model.isConnected)
        #expect(!model.isBusy)
    }

    @Test @MainActor func disconnectedRefreshCannotOverwriteNewConnection() async {
        let previous = ControlledRPC(hold: .refresh, torrents: [fixtureTorrent(1)])
        let replacement = ControlledRPC(hold: .none, torrents: [fixtureTorrent(2)])
        let model = TreManaModel(makeClient: { connection in
            connection.url.host == "old.example" ? previous : replacement
        })
        model.rpcURL = "https://old.example/transmission/rpc"
        await model.connect()
        #expect(model.isConnected)
        #expect(model.torrents.map(\.id) == [1])

        let oldRefresh = Task { await model.refresh() }
        await previous.waitForHeldCall()
        model.disconnect()
        model.rpcURL = "https://new.example/transmission/rpc"
        await model.connect()

        #expect(model.torrents.map(\.id) == [2])
        await previous.resumeHeldCall()
        await oldRefresh.value
        #expect(model.torrents.map(\.id) == [2])
        #expect(model.isConnected)
        #expect(!model.isBusy)
        #expect(model.errorMessage == nil)
    }

    @Test @MainActor func staleConnectDoesNotClearNewConnectionsBusyState() async {
        let first = ControlledRPC(hold: .session, torrents: [fixtureTorrent(1)])
        let second = ControlledRPC(hold: .session, torrents: [fixtureTorrent(2)])
        let model = TreManaModel(makeClient: { connection in
            connection.url.host == "first.example" ? first : second
        })

        model.rpcURL = "https://first.example/transmission/rpc"
        let firstTask = Task { await model.connect() }
        await first.waitForHeldCall()

        model.disconnect()
        model.rpcURL = "https://second.example/transmission/rpc"
        let secondTask = Task { await model.connect() }
        await second.waitForHeldCall()

        await first.resumeHeldCall()
        await firstTask.value
        #expect(model.isBusy)
        #expect(!model.isConnected)

        await second.resumeHeldCall()
        await secondTask.value
        #expect(model.isConnected)
        #expect(model.torrents.map(\.id) == [2])
        #expect(!model.isBusy)
    }

    @Test @MainActor func pauseIsNeverDroppedDuringBackgroundPolling() async {
        let remote = ControlledRPC(hold: .refresh, torrents: [fixtureTorrent(1)])
        let model = TreManaModel(makeClient: { _ in remote })
        model.rpcURL = "https://router.example/transmission/rpc"
        await model.connect()
        model.selectedTorrentIDs = [1]

        let pendingPoll = Task { await model.refresh() }
        await remote.waitForHeldCall()
        #expect(model.isRefreshing)
        #expect(!model.isBusy)

        // Previous implementation shared isBusy with polling and silently
        // discarded this action; it must reach the daemon while GET is pending.
        await model.perform(.stop)
        let performed = await remote.performedActions()
        #expect(performed.count == 1)
        #expect(performed.first?.method == "torrent-stop")
        #expect(performed.first?.ids == [1])
        #expect(!model.isBusy)

        await remote.resumeHeldCall()
        await pendingPoll.value
        #expect(!model.isRefreshing)
        #expect(model.isConnected)
        #expect(model.errorMessage == nil)
    }

    @Test @MainActor func actionsAreLimitedToExistingSelectedTorrents() async {
        let remote = ControlledRPC(
            hold: .none, torrents: [fixtureTorrent(1), fixtureTorrent(2)]
        )
        let model = TreManaModel(makeClient: { _ in remote })
        model.rpcURL = "https://router.example/transmission/rpc"
        await model.connect()

        model.selectedTorrentIDs = [2, 999]
        await model.perform(.stop)

        let calls = await remote.performedActions()
        #expect(calls.count == 1)
        #expect(calls.first?.method == "torrent-stop")
        #expect(calls.first?.ids == [2])
        #expect(model.selectedTorrentIDs == [2])

        model.selectedTorrentIDs = []
        await model.perform(.start)
        #expect(await remote.performedActions().count == 1)

        model.disconnect()
        #expect(model.selectedTorrentIDs.isEmpty)
    }

    @Test @MainActor func pendingActionCannotRestoreStateAfterDisconnect() async {
        let remote = ControlledRPC(hold: .action, torrents: [fixtureTorrent(1)])
        let model = TreManaModel(makeClient: { _ in remote })
        model.rpcURL = "https://router.example/transmission/rpc"
        await model.connect()
        model.selectedTorrentIDs = [1]

        let task = Task { await model.perform(.verify) }
        await remote.waitForHeldCall()
        model.disconnect()
        await remote.resumeHeldCall()
        await task.value

        #expect(!model.isConnected)
        #expect(!model.isBusy)
        #expect(model.errorMessage == nil)
        #expect(model.torrents.isEmpty)
        #expect(model.selectedTorrentIDs.isEmpty)
    }

    @Test @MainActor func staleNetworkErrorDoesNotAppearAfterDisconnect() async {
        let remote = ControlledRPC(hold: .session, torrents: [])
        let model = TreManaModel(makeClient: { _ in remote })
        model.rpcURL = "https://router.example/transmission/rpc"

        let task = Task { await model.connect() }
        await remote.waitForHeldCall()
        model.disconnect()
        await remote.failHeldCall()
        await task.value
        #expect(model.errorMessage == nil)
        #expect(!model.isConnected)
    }
}

private func fixtureTorrent(_ id: Int) -> TransmissionTorrent {
    TransmissionTorrent(
        id: id, name: "Torrent \(id)", status: 4, percentDone: 0.5,
        rateDownload: 1, rateUpload: 0, sizeWhenDone: 10, eta: 5,
        errorString: ""
    )
}

private actor ControlledRPC: TransmissionRPCProviding {
    enum Hold: Sendable {
        case none
        case session
        case initialTorrents
        case refresh
        case action
    }

    let hold: Hold
    let contents: [TransmissionTorrent]
    private var torrentCalls = 0
    private var recordedActions: [(method: String, ids: [Int])] = []
    private var actionContinuation: CheckedContinuation<Void, Error>?
    private var sessionContinuation: CheckedContinuation<TransmissionSession, Error>?
    private var torrentContinuation: CheckedContinuation<[TransmissionTorrent], Error>?
    private var startedContinuation: CheckedContinuation<Void, Never>?

    init(hold: Hold, torrents: [TransmissionTorrent]) {
        self.hold = hold
        self.contents = torrents
    }

    func addTorrent(
        _ source: TorrentAddSource,
        startImmediately: Bool
    ) async throws -> TorrentAddOutcome {
        .added(TransmissionAddedTorrent(
            id: 33, name: "Added via test",
            hashString: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        ))
    }

    func torrentDetails(id: Int) async throws -> TransmissionTorrentDetail? { nil }

    func perform(_ action: TorrentAction, ids: [Int]) async throws {
        recordedActions.append((method: action.rawValue, ids: ids))
        if hold == .action {
            try await withCheckedThrowingContinuation { continuation in
                actionContinuation = continuation
                startedContinuation?.resume()
                startedContinuation = nil
            }
        }
    }

    func performedActions() -> [(method: String, ids: [Int])] {
        recordedActions
    }

    func sessionInfo() async throws -> TransmissionSession {
        if hold == .session {
            return try await withCheckedThrowingContinuation { continuation in
                sessionContinuation = continuation
                startedContinuation?.resume()
                startedContinuation = nil
            }
        }
        return TransmissionSession(version: "3.00", rpcVersion: 16)
    }

    func torrents() async throws -> [TransmissionTorrent] {
        torrentCalls += 1
        let suspend = (hold == .initialTorrents && torrentCalls == 1)
            || (hold == .refresh && torrentCalls == 2)

        if suspend {
            return try await withCheckedThrowingContinuation { continuation in
                torrentContinuation = continuation
                startedContinuation?.resume()
                startedContinuation = nil
            }
        }
        return contents
    }

    func waitForHeldCall() async {
        guard sessionContinuation == nil, torrentContinuation == nil,
              actionContinuation == nil else {
            return
        }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func resumeHeldCall() {
        sessionContinuation?.resume(
            returning: TransmissionSession(version: "3.00", rpcVersion: 16)
        )
        sessionContinuation = nil
        torrentContinuation?.resume(returning: contents)
        torrentContinuation = nil
        actionContinuation?.resume()
        actionContinuation = nil
    }

    func failHeldCall() {
        sessionContinuation?.resume(throwing: TransmissionRPCError.unauthorized)
        sessionContinuation = nil
        torrentContinuation?.resume(throwing: TransmissionRPCError.unauthorized)
        torrentContinuation = nil
        actionContinuation?.resume(throwing: TransmissionRPCError.unauthorized)
        actionContinuation = nil
    }
}

@MainActor
private final class ConnectionCapture {
    var connection: TransmissionConnection?
}

private actor DeniedPasswords: RPCPasswordStoring {
    func read(for id: UUID) async throws -> String? { nil }
    func upsert(_ password: String, for id: UUID) async throws {
        throw ProfileStorageError.keychainFailure(-34018)
    }
    func remove(for id: UUID) async throws {}
}
