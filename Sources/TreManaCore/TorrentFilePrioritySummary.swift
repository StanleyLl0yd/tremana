import Foundation

/// Read-only roll-up of the actual Transmission 3.00 per-file priorities.
/// Transmission RPC 16 cannot set one independent "torrent priority"; it
/// only accepts file indices, so this value must never act as an edit control.
public enum TorrentFilePrioritySummary: String, Sendable, Equatable {
    case unknown
    case low
    case normal
    case high
    case mixed

    public init(fileStats: [TransmissionTorrentFileStat]?) {
        guard let fileStats, !fileStats.isEmpty,
              fileStats.allSatisfy({ (-1...1).contains($0.priority) }) else {
            self = .unknown
            return
        }
        let first = fileStats[0].priority
        guard fileStats.allSatisfy({ $0.priority == first }) else {
            self = .mixed
            return
        }
        switch first {
        case -1: self = .low
        case 0: self = .normal
        case 1: self = .high
        default: self = .unknown
        }
    }
}
