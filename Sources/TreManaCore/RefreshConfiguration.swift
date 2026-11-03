import Foundation

public enum RefreshPreferenceKeys {
    public static let enabled = "com.sl.tremana.refresh.enabled"
    public static let mode = "com.sl.tremana.refresh.mode"
    public static let fixedInterval = "com.sl.tremana.refresh.fixed-interval"
}

public enum RefreshMode: String, Codable, CaseIterable, Sendable {
    case adaptive
    case fixed
}

public struct RefreshConfiguration: Equatable, Sendable {
    public static let allowedFixedIntervals = [5, 10, 15, 30]

    public let enabled: Bool
    public let mode: RefreshMode
    public let fixedIntervalSeconds: Int

    public init(
        enabled: Bool = true,
        mode: RefreshMode = .adaptive,
        fixedIntervalSeconds: Int = 10
    ) {
        self.enabled = enabled
        self.mode = mode
        self.fixedIntervalSeconds = Self.allowedFixedIntervals.contains(fixedIntervalSeconds)
            ? fixedIntervalSeconds : 10
    }

    public func intervalSeconds(
        torrents: [TransmissionTorrent],
        isForeground: Bool,
        hadError: Bool = false
    ) -> Int? {
        guard enabled else { return nil }

        let interval = switch mode {
        case .adaptive:
            RefreshPolicy.intervalSeconds(
                torrents: torrents,
                isForeground: true,
                hadError: false
            )
        case .fixed:
            fixedIntervalSeconds
        }

        // Even fixed mode throttles in inactive windows or after RPC failures,
        // avoiding unnecessary traffic to a resource-constrained router.
        return (!isForeground || hadError) ? max(30, interval) : interval
    }
}
