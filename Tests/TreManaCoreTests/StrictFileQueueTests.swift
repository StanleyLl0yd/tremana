import Testing
@testable import TreManaCore

@Suite("Strict file queue planning")
struct StrictFileQueueTests {
    @Test func selectsFirstIncompleteFileInUserOrder() throws {
        let plan = try StrictFileQueuePlanner.plan(
            orderedSelectedIndices: [2, 0, 1],
            files: [
                QueuedFile(index: 0, length: 10, bytesCompleted: 0),
                QueuedFile(index: 1, length: 10, bytesCompleted: 0),
                QueuedFile(index: 2, length: 10, bytesCompleted: 10)
            ]
        )
        #expect(plan.activeFileIndex == 0)
        #expect(plan.unwantedFileIndices == [1, 2])
        let args = try #require(plan.rpcUpdateArguments(torrentID: 11))
        #expect(args.keys.contains("files-wanted"))
        #expect(args.keys.contains("files-unwanted"))
        #expect(!args.keys.contains("priority-high"))
        #expect(!args.keys.contains("priority-low"))
    }

    @Test func completionNeverEmitsEmptyWantedArray() throws {
        let plan = try StrictFileQueuePlanner.plan(
            orderedSelectedIndices: [0],
            files: [QueuedFile(index: 0, length: 100, bytesCompleted: 100)]
        )
        #expect(plan.isFinished)
        #expect(plan.rpcUpdateArguments(torrentID: 3) == nil)
    }

    @Test func rejectsDuplicateOrUnknownFiles() throws {
        let files = [QueuedFile(index: 0, length: 10, bytesCompleted: 0)]
        #expect(throws: StrictFileQueueError.invalidSelection) {
            _ = try StrictFileQueuePlanner.plan(
                orderedSelectedIndices: [0, 0], files: files
            )
        }
        #expect(throws: StrictFileQueueError.invalidSelection) {
            _ = try StrictFileQueuePlanner.plan(
                orderedSelectedIndices: [1], files: files
            )
        }
    }
}
