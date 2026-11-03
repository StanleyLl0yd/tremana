import Testing
@testable import TreManaCore

@Suite("Refresh configuration")
struct RefreshConfigurationTests {
    @Test func defaultIsEnabledAndAdaptive() {
        let settings = RefreshConfiguration()
        #expect(settings.enabled)
        #expect(settings.mode == .adaptive)
        #expect(settings.fixedIntervalSeconds == 10)
        #expect(settings.intervalSeconds(torrents: [torrent(status: 4)], isForeground: true) == 5)
        #expect(settings.intervalSeconds(torrents: [], isForeground: true) == 15)
    }

    @Test(arguments: [5, 10, 15, 30])
    func fixedIntervalsAreExactInForeground(_ seconds: Int) {
        let settings = RefreshConfiguration(
            enabled: true, mode: .fixed, fixedIntervalSeconds: seconds
        )
        #expect(settings.intervalSeconds(
            torrents: [torrent(status: 4)], isForeground: true
        ) == seconds)
        #expect(settings.intervalSeconds(torrents: [], isForeground: true) == seconds)
    }

    @Test func disabledModeDoesNotSchedulePolling() {
        for mode in RefreshMode.allCases {
            let settings = RefreshConfiguration(enabled: false, mode: mode)
            #expect(settings.intervalSeconds(torrents: [torrent(status: 4)], isForeground: true) == nil)
            #expect(settings.intervalSeconds(torrents: [], isForeground: false) == nil)
        }
    }

    @Test func inactiveOrErrorStateThrottlesFixedPolling() {
        let settings = RefreshConfiguration(mode: .fixed, fixedIntervalSeconds: 5)
        #expect(settings.intervalSeconds(torrents: [torrent(status: 4)], isForeground: false) == 30)
        #expect(settings.intervalSeconds(torrents: [torrent(status: 4)], isForeground: true, hadError: true) == 30)
    }

    @Test func invalidPersistedFixedIntervalUsesSafeDefault() {
        #expect(RefreshConfiguration(mode: .fixed, fixedIntervalSeconds: -5).fixedIntervalSeconds == 10)
        #expect(RefreshConfiguration(mode: .fixed, fixedIntervalSeconds: 1).fixedIntervalSeconds == 10)
        #expect(RefreshConfiguration(mode: .fixed, fixedIntervalSeconds: 1000).fixedIntervalSeconds == 10)
    }

    private func torrent(status: Int) -> TransmissionTorrent {
        TransmissionTorrent(
            id: 1, name: "Fixture", status: status, percentDone: 0.1,
            rateDownload: 0, rateUpload: 0, sizeWhenDone: 10, eta: 10,
            errorString: ""
        )
    }
}
