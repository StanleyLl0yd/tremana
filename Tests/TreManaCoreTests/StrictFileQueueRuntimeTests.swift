import Foundation
import Testing
@testable import TreManaCore

@Suite("Durable strict file order")
struct StrictFileQueueRuntimeTests {
    @Test @MainActor func advancesOnlyOnCompletionAndRestoresOriginalSelection() async throws {
        let name = "TreMana.StrictQueue.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let rpc = QueueMockRPC()
        let endpoint = "https://home.example/transmission/rpc"
        let controller = StrictFileQueueController(defaults: defaults)
        try await controller.setEnabled(true, torrentID: 1, endpoint: endpoint, client: rpc)
        #expect(controller.enabledTorrentIDs(endpoint: endpoint) == Set([1]))
        #expect(await rpc.wanted() == [true, false, false])

        let restarted = StrictFileQueueController(defaults: defaults)
        #expect(restarted.enabledTorrentIDs(endpoint: endpoint) == Set([1]))
        try await restarted.advance(endpoint: endpoint, client: rpc)
        #expect(await rpc.wanted() == [true, false, false])

        await rpc.completeFile(0)
        try await restarted.advance(endpoint: endpoint, client: rpc)
        #expect(await rpc.wanted() == [false, true, false])
        await rpc.completeFile(1)
        try await restarted.advance(endpoint: endpoint, client: rpc)
        #expect(await rpc.wanted() == [false, false, true])
        await rpc.completeFile(2)
        try await restarted.advance(endpoint: endpoint, client: rpc)
        #expect(await rpc.wanted() == [true, true, true])
        #expect(restarted.enabledTorrentIDs(endpoint: endpoint).isEmpty)
        #expect(await rpc.mutations() == 4)
    }

    @Test @MainActor func externalFileSelectionDriftStopsQueue() async throws {
        let name = "TreMana.StrictQueue.Drift.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let rpc = QueueMockRPC()
        let endpoint = "https://home.example/transmission/rpc"
        let controller = StrictFileQueueController(defaults: defaults)
        try await controller.setEnabled(true, torrentID: 1, endpoint: endpoint, client: rpc)
        await rpc.changeWanted([true, true, false])

        do {
            try await controller.advance(endpoint: endpoint, client: rpc)
            Issue.record("External changes must not be overwritten")
        } catch let error as TransmissionRPCError {
            #expect(error == .fileSelectionChanged)
        }
        #expect(await rpc.wanted() == [true, true, false])
        #expect(await rpc.mutations() == 1)
    }

    @Test @MainActor func userCanDisableAndRestoreSelection() async throws {
        let name = "TreMana.StrictQueue.Disable.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let rpc = QueueMockRPC()
        let controller = StrictFileQueueController(defaults: defaults)
        let endpoint = "https://home.example/transmission/rpc"
        try await controller.setEnabled(true, torrentID: 1, endpoint: endpoint, client: rpc)
        try await controller.setEnabled(false, torrentID: 1, endpoint: endpoint, client: rpc)
        #expect(await rpc.wanted() == [true, true, true])
        #expect(controller.enabledTorrentIDs(endpoint: endpoint).isEmpty)
    }
}

private actor QueueMockRPC: TransmissionRPCProviding {
    private var wantedStates = [true, true, true]
    private var completed = [0, 0, 0]
    private var callCount = 0

    func wanted() -> [Bool] { wantedStates }
    func mutations() -> Int { callCount }

    func completeFile(_ index: Int) {
        completed[index] = 10
    }

    func changeWanted(_ newStates: [Bool]) {
        wantedStates = newStates
    }

    func setQueueFileSelection(
        torrentID: Int, wanted: [Int], unwanted: [Int]
    ) async throws {
        guard torrentID == 1 else { throw TransmissionRPCError.invalidTorrentSelection }
        callCount += 1
        for index in wanted {
            wantedStates[index] = true
        }
        for index in unwanted {
            wantedStates[index] = false
        }
    }

    func torrentDetails(id: Int) async throws -> TransmissionTorrentDetail? {
        guard id == 1 else { return nil }
        let payload: [String: Any] = [
            "id": id, "name": "Demo", "status": 4,
            "hashString": String(repeating: "a", count: 40),
            "downloadDir": "/mnt/downloads",
            "files": (0..<3).map { idx in
                ["name": "file_\(idx).mkv", "length": 10, "bytesCompleted": completed[idx]]
            },
            "fileStats": wantedStates.map { wanted in
                ["wanted": wanted, "priority": 0]
            }
        ]
        return try JSONDecoder().decode(
            TransmissionTorrentDetail.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )
    }

    func sessionInfo() async throws -> TransmissionSession {
        TransmissionSession(version: "3.00", rpcVersion: 16)
    }

    func torrents() async throws -> [TransmissionTorrent] { [] }

    func perform(_ action: TorrentAction, ids: [Int]) async throws {}

    func addTorrent(
        _ source: TorrentAddSource, startImmediately: Bool
    ) async throws -> TorrentAddOutcome {
        throw TransmissionRPCError.invalidTorrentMetainfo
    }
}
