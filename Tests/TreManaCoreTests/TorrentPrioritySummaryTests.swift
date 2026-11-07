import Foundation
import Testing
@testable import TreManaCore

@Suite("Torrent priority summary")
struct TorrentPrioritySummaryTests {
    private func decode(_ values: [Int], wanted: [Bool]? = nil) throws -> [TransmissionTorrentFileStat] {
        let dicts: [[String: Any]] = values.enumerated().map { index, priority in
            ["wanted": wanted?[index] ?? (index != 2),
             "priority": priority, "bytesCompleted": 0]
        }
        return try JSONDecoder().decode(
            [TransmissionTorrentFileStat].self,
            from: JSONSerialization.data(withJSONObject: dicts)
        )
    }

    @Test func summaryRepresentsEffectiveDownloadState() throws {
        #expect(TorrentFilePrioritySummary(fileStats: try decode([-1, -1])) == .low)
        #expect(TorrentFilePrioritySummary(fileStats: try decode([0, 0])) == .normal)
        #expect(TorrentFilePrioritySummary(fileStats: try decode([1, 1])) == .high)
        #expect(TorrentFilePrioritySummary(fileStats: try decode([0, 0], wanted: [false, false])) == .skipped)
        #expect(TorrentFilePrioritySummary(fileStats: try decode([0, 0], wanted: [true, false])) == .mixed)
        #expect(TorrentFilePrioritySummary(fileStats: try decode([1, 0, -1])) == .mixed)
        // Skipping a file changes its effective status, not its stored RPC priority.
        #expect(TorrentFilePrioritySummary(priorities: [1, 1, 0]) == .mixed)
    }

    @Test func missingOrInvalidMetadataNeverDefaultsToNormal() throws {
        #expect(TorrentFilePrioritySummary(fileStats: nil) == .unknown)
        #expect(TorrentFilePrioritySummary(fileStats: []) == .unknown)
        #expect(TorrentFilePrioritySummary(fileStats: try decode([2])) == .unknown)
    }

    @Test func torrentListDecodesFilePrioritySummary() throws {
        let json = #"""
        {"id":8,"name":"Files","status":4,"percentDone":0.5,"rateDownload":300,
        "rateUpload":50,"sizeWhenDone":1200,"eta":12,"errorString":"",
        "fileStats":[{"wanted":true,"priority":1},{"wanted":false,"priority":0}]}
        """#
        let torrent = try JSONDecoder().decode(
            TransmissionTorrent.self, from: Data(json.utf8)
        )
        #expect(torrent.filePrioritySummary == .mixed)
    }
}
