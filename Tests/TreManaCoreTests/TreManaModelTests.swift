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

    @Test @MainActor func switchingSelectionRejectsLateInspectorData() async throws {
        let remote = ControlledRPC(
            hold: .detail,
            torrents: [fixtureTorrent(1), fixtureTorrent(2)]
        )
        let model = TreManaModel(makeClient: { _ in remote })
        model.rpcURL = "https://router.example/transmission/rpc"
        await model.connect()

        model.selectedTorrentIDs = [1]
        let original = Task { await model.loadSelectedTorrentDetails() }
        await remote.waitForHeldCall()

        model.selectedTorrentIDs = [2]
        await model.loadSelectedTorrentDetails()
        #expect(model.selectedTorrentDetail?.id == 2)
        await remote.resumeHeldCall()
        await original.value
        #expect(model.selectedTorrentDetail?.id == 2)
        #expect(model.detailErrorMessage == nil)

        model.selectedTorrentIDs = []
        await model.loadSelectedTorrentDetails()
        #expect(model.selectedTorrentDetail == nil)
    }

    @Test @MainActor func disconnectRejectsPendingInspectorResponse() async {
        let remote = ControlledRPC(hold: .detail, torrents: [fixtureTorrent(1)])
        let model = TreManaModel(makeClient: { _ in remote })
        model.rpcURL = "https://router.example/transmission/rpc"
        await model.connect()
        model.selectedTorrentIDs = [1]

        let original = Task { await model.loadSelectedTorrentDetails() }
        await remote.waitForHeldCall()
        model.disconnect()
        await remote.resumeHeldCall()
        await original.value
        #expect(!model.isConnected)
        #expect(!model.isLoadingDetail)
        #expect(model.selectedTorrentDetail == nil)
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

    @Test @MainActor func contextMenuRefusesStaleOrUnknownIDs() async {
        let remote = ControlledRPC(hold: .none, torrents: [fixtureTorrent(2)])
        let model = TreManaModel(makeClient: { _ in remote })
        model.rpcURL = "https://router.example/transmission/rpc"
        await model.connect()

        await model.perform(.stop, ids: [2, 999])
        #expect(await remote.performedActions().isEmpty)
        #expect(model.errorMessage != nil)

        await model.perform(.startNow, ids: [2])
        let calls = await remote.performedActions()
        #expect(calls.count == 1)
        #expect(calls.first?.method == "torrent-start-now")
        #expect(calls.first?.ids == [2])
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

    @Test @MainActor func filePriorityConfirmsServerAndRejectsStaleValue() async {
        let remote = ControlledRPC(
            hold: .none, torrents: [fixtureTorrent(1)], wantedStates: [true, true]
        )
        let model = TreManaModel(makeClient: { _ in remote })
        model.rpcURL = "https://router.example/transmission/rpc"
        await model.connect()
        model.selectedTorrentIDs = [1]
        await model.loadSelectedTorrentDetails()

        await model.setFilePriority(
            torrentID: 1, fileIndex: 1, priority: 1, expectedPriority: 0
        )
        #expect(await remote.filePriorityCalls().count == 1)
        #expect(model.selectedTorrentDetail?.fileStats?[1].priority == 1)
        #expect(model.noticeMessage == "File priority updated")

        await remote.replacePriorityStates([0, -1])
        await model.setFilePriority(
            torrentID: 1, fileIndex: 1, priority: 0, expectedPriority: 1
        )
        #expect(await remote.filePriorityCalls().count == 1)
        #expect(model.selectedTorrentDetail?.fileStats?[1].priority == -1)
        #expect(model.errorMessage == TransmissionRPCError.invalidFilePriority.localizedDescription)

        await model.setFilePriority(
            torrentID: 1, fileIndex: 1, priority: 5, expectedPriority: -1
        )
        #expect(await remote.filePriorityCalls().count == 1)
    }

    @Test @MainActor func fileWantedToggleConfirmsServerAndPreservesLastFile() async {
        let remote = ControlledRPC(
            hold: .none, torrents: [fixtureTorrent(1)], wantedStates: [true, true]
        )
        let model = TreManaModel(makeClient: { _ in remote })
        model.rpcURL = "https://router.example/transmission/rpc"
        await model.connect()
        model.selectedTorrentIDs = [1]
        await model.loadSelectedTorrentDetails()

        await model.setFileWanted(
            torrentID: 1, fileIndex: 1, wanted: false, expectedWanted: true
        )
        #expect(await remote.fileSelectionCalls().count == 1)
        #expect(model.selectedTorrentDetail?.fileStats?[1].wanted == false)
        #expect(model.noticeMessage == "File selection updated")
        #expect(!model.isBusy)

        await model.setFileWanted(
            torrentID: 1, fileIndex: 0, wanted: false, expectedWanted: true
        )
        #expect(await remote.fileSelectionCalls().count == 1)
        #expect(model.selectedTorrentDetail?.fileStats?[0].wanted == true)
        #expect(model.errorMessage == TransmissionRPCError.lastWantedFile.localizedDescription)
    }

    @Test @MainActor func fileToggleRefusesInvalidOrStaleInspectorSelection() async {
        let remote = ControlledRPC(
            hold: .none, torrents: [fixtureTorrent(1), fixtureTorrent(2)],
            wantedStates: [true, true]
        )
        let model = TreManaModel(makeClient: { _ in remote })
        model.rpcURL = "https://router.example/transmission/rpc"
        await model.connect()
        model.selectedTorrentIDs = [1]
        await model.loadSelectedTorrentDetails()

        await model.setFileWanted(
            torrentID: 1, fileIndex: 9, wanted: false, expectedWanted: true
        )
        await model.setFileWanted(
            torrentID: 2, fileIndex: 0, wanted: false, expectedWanted: true
        )
        await model.setFileWanted(
            torrentID: 1, fileIndex: 0, wanted: true, expectedWanted: true
        )
        #expect(await remote.fileSelectionCalls().isEmpty)

        // Another Transmission client changed the server since last refresh.
        await remote.replaceWantedStates([false, true])
        await model.setFileWanted(
            torrentID: 1, fileIndex: 0, wanted: false, expectedWanted: true
        )
        #expect(await remote.fileSelectionCalls().isEmpty)
        #expect(model.selectedTorrentDetail?.fileStats?[0].wanted == false)
        #expect(model.errorMessage == TransmissionRPCError.fileSelectionChanged.localizedDescription)

        await remote.replaceWantedStates([true, true])
        await model.loadSelectedTorrentDetails()
        await remote.renameTestFiles()
        await model.setFileWanted(
            torrentID: 1, fileIndex: 1, wanted: false, expectedWanted: true
        )
        #expect(await remote.fileSelectionCalls().isEmpty)
        #expect(model.errorMessage == TransmissionRPCError.invalidFileSelection.localizedDescription)
    }

    @Test @MainActor func fileToggleResponseCannotLeakAcrossSelectionSwitch() async {
        let remote = ControlledRPC(
            hold: .fileAction, torrents: [fixtureTorrent(1), fixtureTorrent(2)],
            wantedStates: [true, true]
        )
        let model = TreManaModel(makeClient: { _ in remote })
        model.rpcURL = "https://router.example/transmission/rpc"
        await model.connect()
        model.selectedTorrentIDs = [1]
        await model.loadSelectedTorrentDetails()

        let pending = Task {
            await model.setFileWanted(
                torrentID: 1, fileIndex: 1, wanted: false, expectedWanted: true
            )
        }
        await remote.waitForHeldCall()
        model.selectedTorrentIDs = [2]
        await model.loadSelectedTorrentDetails()
        #expect(model.selectedTorrentDetail?.id == 2)

        await remote.resumeHeldCall()
        await pending.value
        #expect(model.selectedTorrentDetail?.id == 2)
        #expect(model.errorMessage == nil)
        #expect(!model.isBusy)
    }

    @Test @MainActor func disconnectedFileToggleCannotRestoreOldState() async {
        let remote = ControlledRPC(
            hold: .fileAction, torrents: [fixtureTorrent(1)],
            wantedStates: [true, true]
        )
        let model = TreManaModel(makeClient: { _ in remote })
        model.rpcURL = "https://router.example/transmission/rpc"
        await model.connect()
        model.selectedTorrentIDs = [1]
        await model.loadSelectedTorrentDetails()

        let pending = Task {
            await model.setFileWanted(
                torrentID: 1, fileIndex: 1, wanted: false, expectedWanted: true
            )
        }
        await remote.waitForHeldCall()
        model.disconnect()
        await remote.resumeHeldCall()
        await pending.value
        #expect(!model.isConnected)
        #expect(model.selectedTorrentDetail == nil)
        #expect(model.errorMessage == nil)
        #expect(model.noticeMessage == nil)
        #expect(!model.isBusy)
    }

    @Test @MainActor func failedFileRPCDoesNotOptimisticallyChangeCheckbox() async {
        let remote = ControlledRPC(
            hold: .none, torrents: [fixtureTorrent(1)],
            wantedStates: [true, true], rejectFileChanges: true
        )
        let model = TreManaModel(makeClient: { _ in remote })
        model.rpcURL = "https://router.example/transmission/rpc"
        await model.connect()
        model.selectedTorrentIDs = [1]
        await model.loadSelectedTorrentDetails()

        await model.setFileWanted(
            torrentID: 1, fileIndex: 1, wanted: false, expectedWanted: true
        )
        #expect(await remote.fileSelectionCalls().count == 1)
        #expect(model.selectedTorrentDetail?.fileStats?[1].wanted == true)
        #expect(model.errorMessage == TransmissionRPCError.serverError("read only").localizedDescription)
        #expect(!model.isBusy)
    }


    @Test @MainActor func remoteMoveRejectsChangedServerLocation() async throws {
        let remote = ControlledRPC(hold: .none, torrents: [fixtureTorrent(1)])
        let model = TreManaModel(makeClient: { _ in remote })
        model.rpcURL = "https://router.example/transmission/rpc"
        await model.connect()
        let snapshot = try #require(await model.remoteActionDetail(for: 1))
        await remote.updateRemoteDownloadDir("/mnt/changed-by-other-client")

        let success = await model.moveTorrent(
            to: "/mnt/new-location", expected: snapshot
        )
        #expect(!success)
        #expect(await remote.remoteMoveCalls().isEmpty)
        #expect(model.errorMessage == TransmissionRPCError.remoteStateChanged.localizedDescription)
    }

    @Test @MainActor func moveConfirmsOneTorrentAndRefreshesRemoteLocation() async throws {
        let remote = ControlledRPC(hold: .none, torrents: [fixtureTorrent(1)])
        let model = TreManaModel(makeClient: { _ in remote })
        model.rpcURL = "https://router.example/transmission/rpc"
        await model.connect()
        model.selectedTorrentIDs = [1]
        let snapshot = try #require(await model.remoteActionDetail(for: 1))

        let success = await model.moveTorrent(
            to: "/mnt/archive", expected: snapshot
        )
        #expect(success)
        let calls = await remote.remoteMoveCalls()
        #expect(calls.count == 1)
        #expect(calls.first?.torrentID == 1)
        #expect(calls.first?.destination == "/mnt/archive")
        #expect(model.selectedTorrentDetail?.downloadDir == "/mnt/archive")
        #expect(model.noticeMessage == "Server move confirmed")
    }

    @Test @MainActor func remoteRenameIsBoundToExistingFileMetadata() async throws {
        let remote = ControlledRPC(
            hold: .none, torrents: [fixtureTorrent(1)], wantedStates: [true, true]
        )
        let model = TreManaModel(makeClient: { _ in remote })
        model.rpcURL = "https://router.example/transmission/rpc"
        await model.connect()
        model.selectedTorrentIDs = [1]
        let snapshot = try #require(await model.remoteActionDetail(for: 1))

        let invalid = await model.renameTorrentPath(
            "not-in-torrent", to: "unrelated", expected: snapshot
        )
        #expect(!invalid)
        #expect(await remote.remoteRenameCalls().isEmpty)

        let success = await model.renameTorrentPath(
            "file_0", to: "renamed_file", expected: snapshot
        )
        #expect(success)
        let calls = await remote.remoteRenameCalls()
        #expect(calls.count == 1)
        #expect(calls.first?.torrentID == 1)
        #expect(calls.first?.path == "file_0")
        #expect(calls.first?.name == "renamed_file")
        #expect(model.selectedTorrentDetail?.files?[0].name == "renamed_file")
        #expect(model.noticeMessage == "Server path rename confirmed")
    }

    @Test @MainActor func remoteRenameRefusesStaleFileList() async throws {
        let remote = ControlledRPC(
            hold: .none, torrents: [fixtureTorrent(1)], wantedStates: [true, true]
        )
        let model = TreManaModel(makeClient: { _ in remote })
        model.rpcURL = "https://router.example/transmission/rpc"
        await model.connect()
        let snapshot = try #require(await model.remoteActionDetail(for: 1))
        await remote.renameTestFiles()

        let success = await model.renameTorrentPath(
            "file_0", to: "new_name", expected: snapshot
        )
        #expect(!success)
        #expect(await remote.remoteRenameCalls().isEmpty)
        #expect(model.errorMessage == TransmissionRPCError.remoteStateChanged.localizedDescription)
    }



    @Test @MainActor func moveVerificationFailureWarnsOperationMayHaveApplied() async throws {
        let remote = ControlledRPC(
            hold: .none, torrents: [fixtureTorrent(1)],
            failPostMoveDetail: true
        )
        let model = TreManaModel(makeClient: { _ in remote })
        model.rpcURL = "https://router.example/transmission/rpc"
        await model.connect()
        let snapshot = try #require(await model.remoteActionDetail(for: 1))

        let success = await model.moveTorrent(to: "/mnt/other", expected: snapshot)
        #expect(!success)
        #expect(await remote.remoteMoveCalls().count == 1)
        #expect(model.errorMessage ==
                TransmissionRPCError.remoteMutationUnverified.localizedDescription)
    }

    @Test @MainActor func disconnectDuringRemoteMoveDoesNotRestoreOldUI() async throws {
        let remote = ControlledRPC(hold: .remoteMove, torrents: [fixtureTorrent(1)])
        let model = TreManaModel(makeClient: { _ in remote })
        model.rpcURL = "https://router.example/transmission/rpc"
        await model.connect()
        let snapshot = try #require(await model.remoteActionDetail(for: 1))

        let task = Task {
            await model.moveTorrent(to: "/mnt/other", expected: snapshot)
        }
        await remote.waitForHeldCall()
        model.disconnect()
        await remote.resumeHeldCall()
        let success = await task.value

        #expect(!success)
        #expect(!model.isConnected)
        #expect(model.selectedTorrentDetail == nil)
        #expect(model.noticeMessage == nil)
        #expect(model.errorMessage == nil)
        #expect(!model.isBusy)
        #expect(await remote.remoteMoveCalls().count == 1)
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
        case fileAction
        case remoteMove
        case detail
    }

    let hold: Hold
    let contents: [TransmissionTorrent]
    private var wantedStates: [Bool]?
    private var priorityStates: [Int]?
    private var changedPriorities: [(torrentID: Int, fileIndex: Int, priority: Int)] = []
    private var fileNamePrefix = "file_"
    private var fileNameOverrides: [Int: String] = [:]
    private var remoteDownloadDir = "/mnt/downloads"
    private var moves: [(torrentID: Int, destination: String)] = []
    private var renames: [(torrentID: Int, path: String, name: String)] = []
    private let rejectFileChanges: Bool
    private let failPostMoveDetail: Bool
    private var changedFiles: [(torrentID: Int, fileIndex: Int, wanted: Bool)] = []
    private var torrentCalls = 0
    private var recordedActions: [(method: String, ids: [Int])] = []
    private var actionContinuation: CheckedContinuation<Void, Error>?
    private var fileActionContinuation: CheckedContinuation<Void, Error>?
    private var remoteMoveContinuation: CheckedContinuation<Void, Error>?
    private var detailContinuation: CheckedContinuation<TransmissionTorrentDetail?, Never>?
    private var sessionContinuation: CheckedContinuation<TransmissionSession, Error>?
    private var torrentContinuation: CheckedContinuation<[TransmissionTorrent], Error>?
    private var startedContinuation: CheckedContinuation<Void, Never>?

    init(
        hold: Hold,
        torrents: [TransmissionTorrent],
        wantedStates: [Bool]? = nil,
        rejectFileChanges: Bool = false,
        failPostMoveDetail: Bool = false
    ) {
        self.hold = hold
        self.contents = torrents
        self.wantedStates = wantedStates
        self.priorityStates = wantedStates.map { Array(repeating: 0, count: $0.count) }
        self.rejectFileChanges = rejectFileChanges
        self.failPostMoveDetail = failPostMoveDetail
    }

    func setFileWanted(torrentID: Int, fileIndex: Int, wanted: Bool) async throws {
        changedFiles.append((torrentID, fileIndex, wanted))
        if hold == .fileAction {
            try await withCheckedThrowingContinuation { continuation in
                fileActionContinuation = continuation
                startedContinuation?.resume()
                startedContinuation = nil
            }
        }
        if rejectFileChanges {
            throw TransmissionRPCError.serverError("read only")
        }
        guard var states = wantedStates, states.indices.contains(fileIndex) else {
            throw TransmissionRPCError.invalidFileSelection
        }
        states[fileIndex] = wanted
        wantedStates = states
    }

    func setFilePriority(torrentID: Int, fileIndex: Int, priority: Int) async throws {
        changedPriorities.append((torrentID, fileIndex, priority))
        if rejectFileChanges {
            throw TransmissionRPCError.serverError("read only")
        }
        guard var states = priorityStates, states.indices.contains(fileIndex) else {
            throw TransmissionRPCError.invalidFilePriority
        }
        states[fileIndex] = priority
        priorityStates = states
    }

    func filePriorityCalls() -> [(torrentID: Int, fileIndex: Int, priority: Int)] {
        changedPriorities
    }

    func replacePriorityStates(_ states: [Int]) {
        priorityStates = states
    }

    func fileSelectionCalls() -> [(torrentID: Int, fileIndex: Int, wanted: Bool)] {
        changedFiles
    }

    func replaceWantedStates(_ updated: [Bool]) {
        wantedStates = updated
    }

    func renameTestFiles() {
        fileNamePrefix = "different_"
    }

    func updateRemoteDownloadDir(_ path: String) {
        remoteDownloadDir = path
    }

    func remoteMoveCalls() -> [(torrentID: Int, destination: String)] { moves }
    func remoteRenameCalls() -> [(torrentID: Int, path: String, name: String)] { renames }

    func moveTorrent(torrentID: Int, destination: String) async throws {
        moves.append((torrentID, destination))
        if hold == .remoteMove {
            try await withCheckedThrowingContinuation { continuation in
                remoteMoveContinuation = continuation
                startedContinuation?.resume()
                startedContinuation = nil
            }
        }
        remoteDownloadDir = destination
    }

    func renameTorrentPath(torrentID: Int, path: String, name: String) async throws {
        renames.append((torrentID, path, name))
        guard let count = wantedStates?.count else { return }
        for index in 0..<count {
            if (fileNameOverrides[index] ?? "\(fileNamePrefix)\(index)") == path {
                fileNameOverrides[index] = name
            }
        }
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

    func torrentDetails(id: Int) async throws -> TransmissionTorrentDetail? {
        if failPostMoveDetail && !moves.isEmpty {
            throw TransmissionRPCError.unexpectedStatus(503)
        }
        if hold == .detail && id == 1 {
            return await withCheckedContinuation { continuation in
                detailContinuation = continuation
                startedContinuation?.resume()
                startedContinuation = nil
            }
        }
        return try detailFixture(id)
    }

    private func detailFixture(_ id: Int) throws -> TransmissionTorrentDetail {
        if let wantedStates {
            let files: [[String: Any]] = wantedStates.indices.map { index in
                ["name": fileNameOverrides[index] ?? "\(fileNamePrefix)\(index)",
                 "length": 1, "bytesCompleted": 0]
            }
            let stats: [[String: Any]] = wantedStates.enumerated().map { index, wanted in
                [
                    "wanted": wanted,
                    "priority": priorityStates?[index] ?? 0,
                    "bytesCompleted": 0
                ]
            }
            let payload: [String: Any] = [
                "id": id, "name": "Torrent \(id)", "status": 4,
                "hashString": String(format: "%040x", id),
                "downloadDir": remoteDownloadDir,
                "files": files, "fileStats": stats
            ]
            return try JSONDecoder().decode(
                TransmissionTorrentDetail.self,
                from: JSONSerialization.data(withJSONObject: payload)
            )
        }
        let payload: [String: Any] = [
            "id": id, "name": "Torrent \(id)", "status": 4,
            "hashString": String(format: "%040x", id),
            "downloadDir": remoteDownloadDir
        ]
        return try JSONDecoder().decode(
            TransmissionTorrentDetail.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )
    }


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
              actionContinuation == nil, fileActionContinuation == nil,
              remoteMoveContinuation == nil, detailContinuation == nil else {
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
        fileActionContinuation?.resume()
        fileActionContinuation = nil
        remoteMoveContinuation?.resume()
        remoteMoveContinuation = nil
        detailContinuation?.resume(returning: try? detailFixture(1))
        detailContinuation = nil
    }

    func failHeldCall() {
        sessionContinuation?.resume(throwing: TransmissionRPCError.unauthorized)
        sessionContinuation = nil
        torrentContinuation?.resume(throwing: TransmissionRPCError.unauthorized)
        torrentContinuation = nil
        actionContinuation?.resume(throwing: TransmissionRPCError.unauthorized)
        actionContinuation = nil
        fileActionContinuation?.resume(throwing: TransmissionRPCError.unauthorized)
        fileActionContinuation = nil
        remoteMoveContinuation?.resume(throwing: TransmissionRPCError.unauthorized)
        remoteMoveContinuation = nil
        detailContinuation?.resume(returning: nil)
        detailContinuation = nil
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
