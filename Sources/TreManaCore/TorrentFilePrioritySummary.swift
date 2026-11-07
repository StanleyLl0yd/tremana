import Foundation

/// Read-only roll-up of the actual Transmission 3.00 per-file priorities.
/// Transmission RPC 16 cannot set one independent "torrent priority"; it
/// only accepts file indices, so this value must never act as a torrent edit control.
public enum TorrentFilePrioritySummary: String, Sendable, Equatable {
    case unknown
    case low
    case normal
    case high
    case mixed

    public init(fileStats: [TransmissionTorrentFileStat]?) {
        self.init(priorities: fileStats?.map { Optional($0.priority) } ?? [])
    }

    public init(priorities: [Int?]) {
        guard !priorities.isEmpty,
              priorities.allSatisfy({ value in
                  guard let value else { return false }
                  return (-1...1).contains(value)
              }) else {
            self = .unknown
            return
        }

        let values = priorities.compactMap { $0 }
        guard let first = values.first else {
            self = .unknown
            return
        }
        guard values.allSatisfy({ $0 == first }) else {
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
