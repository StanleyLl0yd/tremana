import Foundation

public struct StrictQueueFileSignature: Codable, Sendable, Equatable {
    public let name: String
    public let length: Int64
}

public struct StrictQueueRecord: Codable, Sendable, Equatable {
    public let endpoint: String
    public let torrentID: Int
    public let infoHash: String
    public let files: [StrictQueueFileSignature]
    public let orderedSelectedIndices: [Int]
    public var activeFileIndex: Int
    public var serverSelectionApplied: Bool

    public init(endpoint: String, detail: TransmissionTorrentDetail) throws {
        guard !endpoint.isEmpty,
              detail.id > 0,
              let hash = detail.hashString, hash.count == 40,
              let entries = detail.files,
              let stats = detail.fileStats,
              entries.count == stats.count, !entries.isEmpty,
              entries.allSatisfy({ $0.length >= 0 && $0.bytesCompleted >= 0
                  && $0.bytesCompleted <= $0.length }) else {
            throw StrictFileQueueError.invalidFiles
        }
        let selected = stats.indices.filter { stats[$0].wanted }
        guard !selected.isEmpty else {
            throw StrictFileQueueError.invalidSelection
        }
        let plan = try StrictFileQueuePlanner.plan(
            orderedSelectedIndices: selected,
            files: entries.indices.map {
                QueuedFile(
                    index: $0, length: entries[$0].length,
                    bytesCompleted: entries[$0].bytesCompleted
                )
            }
        )
        guard let active = plan.activeFileIndex else {
            throw StrictFileQueueError.invalidSelection
        }
        self.endpoint = endpoint
        torrentID = detail.id
        infoHash = hash
        files = entries.map { StrictQueueFileSignature(name: $0.name, length: $0.length) }
        orderedSelectedIndices = selected
        activeFileIndex = active
        serverSelectionApplied = false
    }

    public func matches(_ detail: TransmissionTorrentDetail) -> Bool {
        guard detail.id == torrentID,
              detail.hashString == infoHash,
              let entries = detail.files,
              let stats = detail.fileStats,
              entries.count == files.count,
              stats.count == files.count else { return false }
        return zip(entries, files).allSatisfy { pair in
            let (current, expected) = pair
            return current.name == expected.name && current.length == expected.length
                && current.length >= 0
                && current.bytesCompleted >= 0
                && current.bytesCompleted <= current.length
        }
    }

    public func plan(for detail: TransmissionTorrentDetail) throws -> StrictFileQueuePlan {
        guard matches(detail), let entries = detail.files else {
            throw StrictFileQueueError.invalidFiles
        }
        return try StrictFileQueuePlanner.plan(
            orderedSelectedIndices: orderedSelectedIndices,
            files: entries.indices.map {
                QueuedFile(
                    index: $0, length: entries[$0].length,
                    bytesCompleted: entries[$0].bytesCompleted
                )
            }
        )
    }

    public func wantedMatches(_ detail: TransmissionTorrentDetail, active: Int?) -> Bool {
        guard matches(detail), let stats = detail.fileStats else { return false }
        let selected = Set(active.map { [$0] } ?? orderedSelectedIndices)
        return stats.indices.allSatisfy { stats[$0].wanted == selected.contains($0) }
    }

    public var originalUnwantedIndices: [Int] {
        let selected = Set(orderedSelectedIndices)
        return files.indices.filter { !selected.contains($0) }
    }

    public var allExceptActive: [Int] {
        files.indices.filter { $0 != activeFileIndex }
    }
}
