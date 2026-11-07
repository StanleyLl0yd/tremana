import Foundation

/// Effective download status derived from Transmission's per-file wanted flags
/// and priorities. A skipped file keeps its underlying RPC priority so it can
/// be restored unchanged when it is included in the download again.
public enum TorrentFilePrioritySummary: String, Sendable, Equatable {
    case unknown
    case skipped
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
        if fileStats.allSatisfy({ !$0.wanted }) {
            self = .skipped
            return
        }
        if fileStats.contains(where: { !$0.wanted }) {
            self = .mixed
            return
        }
        self.init(priorities: fileStats.map { Optional($0.priority) })
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
