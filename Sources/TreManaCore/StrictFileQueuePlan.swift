import Foundation

public struct QueuedFile: Sendable, Equatable {
    public let index: Int
    public let length: Int64
    public let bytesCompleted: Int64

    public init(index: Int, length: Int64, bytesCompleted: Int64) {
        self.index = index
        self.length = length
        self.bytesCompleted = bytesCompleted
    }

    public var isComplete: Bool { bytesCompleted >= length }
}

public enum StrictFileQueueError: Error, Equatable, Sendable {
    case invalidFiles
    case invalidSelection
}

public struct StrictFileQueuePlan: Sendable, Equatable {
    public let activeFileIndex: Int?
    public let unwantedFileIndices: [Int]

    public var isFinished: Bool { activeFileIndex == nil }

    // An empty files-wanted/files-unwanted RPC array means ALL files in
    // legacy Transmission RPC. Never send an empty array to mean none.
    public func rpcUpdateArguments(torrentID: Int) -> [String: RPCValue]? {
        guard let activeFileIndex else { return nil }

        var arguments: [String: RPCValue] = [
            "ids": .array([.integer(torrentID)]),
            "files-wanted": .array([.integer(activeFileIndex)])
        ]
        if !unwantedFileIndices.isEmpty {
            arguments["files-unwanted"] = .array(
                unwantedFileIndices.map { .integer($0) }
            )
        }
        return arguments
    }
}

public enum StrictFileQueuePlanner {
    public static func plan(
        orderedSelectedIndices: [Int],
        files: [QueuedFile]
    ) throws -> StrictFileQueuePlan {
        guard files.allSatisfy({
            $0.index >= 0 && $0.length >= 0 &&
            $0.bytesCompleted >= 0 && $0.bytesCompleted <= $0.length
        }), Set(files.map(\.index)).count == files.count else {
            throw StrictFileQueueError.invalidFiles
        }

        let available = Set(files.map(\.index))
        guard !orderedSelectedIndices.isEmpty,
              Set(orderedSelectedIndices).count == orderedSelectedIndices.count,
              orderedSelectedIndices.allSatisfy({ available.contains($0) }) else {
            throw StrictFileQueueError.invalidSelection
        }

        let byIndex = Dictionary(uniqueKeysWithValues: files.map { ($0.index, $0) })
        let active = orderedSelectedIndices.first {
            byIndex[$0]?.isComplete == false
        }
        return StrictFileQueuePlan(
            activeFileIndex: active,
            unwantedFileIndices: active == nil
                ? []
                : files.map(\.index).filter { $0 != active }.sorted()
        )
    }
}
