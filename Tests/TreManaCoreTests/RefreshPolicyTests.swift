import Testing
@testable import TreManaCore

@Suite("Adaptive refresh policy")
struct RefreshPolicyTests {
    @Test(arguments: [1, 2, 4])
    func activeDownloadsOrVerificationPollEveryFiveSeconds(_ status: Int) {
        #expect(RefreshPolicy.intervalSeconds(
            torrents: [torrent(status: status)],
            isForeground: true
        ) == 5)
    }

    @Test(arguments: [0, 3, 5, 6])
    func nonDownloadingStatesPollEveryFifteenSeconds(_ status: Int) {
        #expect(RefreshPolicy.intervalSeconds(
            torrents: [torrent(status: status)],
            isForeground: true
        ) == 15)
    }

    @Test func mixedTorrentListUsesActiveRate() {
        #expect(RefreshPolicy.intervalSeconds(
            torrents: [torrent(status: 6), torrent(status: 4)],
            isForeground: true
        ) == 5)
    }

    @Test func emptyTorrentListIsIdle() {
        #expect(RefreshPolicy.intervalSeconds(
            torrents: [],
            isForeground: true
        ) == 15)
    }

    @Test func inactiveSceneUsesThirtySeconds() {
        #expect(RefreshPolicy.intervalSeconds(
            torrents: [torrent(status: 4)],
            isForeground: false
        ) == 30)
    }

    @Test func transientErrorUsesThirtySecondBackoff() {
        #expect(RefreshPolicy.intervalSeconds(
            torrents: [torrent(status: 4)],
            isForeground: true, hadError: true
        ) == 30)
    }

    private func torrent(status: Int) -> TransmissionTorrent {
        TransmissionTorrent(
            id: status + 1,
            name: "Fixture",
            status: status,
            percentDone: 0.3,
            rateDownload: 1024,
            rateUpload: 0,
            sizeWhenDone: 4096,
            eta: 10,
            errorString: ""
        )
    }
}
