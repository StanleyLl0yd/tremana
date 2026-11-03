import Foundation

public enum RefreshPolicy {
    // Transmission 3.00 / RPC 16 status values: 1/2 verify, 4 download.
    // Queued and seeding torrents do not justify high-frequency polling.
    public static func intervalSeconds(
        torrents: [TransmissionTorrent],
        isForeground: Bool,
        hadError: Bool = false
    ) -> Int {
        if !isForeground || hadError { return 30 }
        return torrents.contains { [1, 2, 4].contains($0.status) } ? 5 : 15
    }
}
