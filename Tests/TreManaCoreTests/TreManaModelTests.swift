import Foundation
import Testing
@testable import TreManaCore

@Suite("Connection lifecycle")
struct TreManaModelTests {
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
    }

    let hold: Hold
    let contents: [TransmissionTorrent]
    private var torrentCalls = 0
    private var sessionContinuation: CheckedContinuation<TransmissionSession, Error>?
    private var torrentContinuation: CheckedContinuation<[TransmissionTorrent], Error>?
    private var startedContinuation: CheckedContinuation<Void, Never>?

    init(hold: Hold, torrents: [TransmissionTorrent]) {
        self.hold = hold
        self.contents = torrents
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
        guard sessionContinuation == nil, torrentContinuation == nil else {
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
    }

    func failHeldCall() {
        sessionContinuation?.resume(throwing: TransmissionRPCError.unauthorized)
        sessionContinuation = nil
        torrentContinuation?.resume(throwing: TransmissionRPCError.unauthorized)
        torrentContinuation = nil
    }
}
