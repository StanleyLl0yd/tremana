import Foundation
import Testing
@testable import TreManaCore

@Suite("Torrent file hierarchy")
struct TorrentFileTreeTests {
    private func entry(
        _ index: Int,
        _ path: String,
        _ length: Int64,
        _ completed: Int64,
        wanted: Bool? = true,
        priority: Int? = 0
    ) -> TorrentFileTreeEntry {
        TorrentFileTreeEntry(
            index: index, path: path, length: length,
            bytesCompleted: completed, wanted: wanted, priority: priority
        )
    }

    @Test func buildsNestedFoldersAndPreservesTransmissionFileIndices() throws {
        let root = TorrentFileTreeBuilder.build(
            rootName: "Original Microsoft Office 2019 x86_x64 RU",
            rootID: "torrent:42",
            entries: [
                entry(0, "Tabletka/MAS/All-In-One-Version-KL/MAS_AIO.cmd", 100, 100),
                entry(1, "Separate-Files-Version/Activators/_ReadMe.txt", 10, 5,
                      wanted: true, priority: -1),
                entry(2, "Separate-Files-Version/Activators/HWID_Activation.cmd", 20, 20,
                      wanted: false, priority: 1),
                entry(3, "LICENSE", 30, 0),
                entry(4, "README.md", 40, 40)
            ]
        )

        #expect(root.name == "Original Microsoft Office 2019 x86_x64 RU")
        #expect(root.isDirectory)
        #expect(root.children?.map(\.name) == [
            "Tabletka", "Separate-Files-Version", "LICENSE", "README.md"
        ])
        #expect(root.fileIndices == [0, 1, 2, 3, 4])
        #expect(root.fileCount == 5)
        #expect(root.length == 200)
        #expect(root.bytesCompleted == 165)
        #expect(abs(root.progress - 0.825) < 0.000_001)
        #expect(root.wantedFileCount == 4)
        #expect(root.wantedSummary == .mixed)
        #expect(root.prioritySummary == .mixed)

        let tabletka = try #require(root.children?.first)
        let mas = try #require(tabletka.children?.first)
        let allInOne = try #require(mas.children?.first)
        #expect(tabletka.fileIndices == [0])
        #expect(allInOne.children?.first?.fileIndex == 0)
        #expect(tabletka.wantedSummary == .wanted)
        #expect(tabletka.prioritySummary == .normal)

        let separate = try #require(root.children?.dropFirst().first)
        let activators = try #require(separate.children?.first)
        #expect(activators.fileIndices == [1, 2])
        #expect(activators.length == 30)
        #expect(activators.bytesCompleted == 25)
        #expect(abs(activators.progress - (25.0 / 30.0)) < 0.000_001)
        #expect(activators.wantedSummary == .mixed)
        #expect(activators.wantedFileCount == 1)
        #expect(activators.prioritySummary == .mixed)
        #expect(activators.children?.map(\.name) == [
            "_ReadMe.txt", "HWID_Activation.cmd"
        ])
        #expect(activators.children?.map(\.fileIndex) == [1, 2])
    }

    @Test func folderSummariesReflectAllDescendantFiles() throws {
        let root = TorrentFileTreeBuilder.build(
            rootName: "Collection",
            entries: [
                entry(8, "Media/one.mkv", 100, 50, wanted: true, priority: 1),
                entry(3, "Media/two.mkv", 200, 200, wanted: true, priority: 1),
                entry(5, "Media/three.mkv", 300, 0, wanted: false, priority: 1)
            ]
        )
        let media = try #require(root.children?.first)
        #expect(media.fileIndices == [3, 5, 8])
        #expect(media.length == 600)
        #expect(media.bytesCompleted == 250)
        #expect(media.wantedFileCount == 2)
        #expect(media.wantedSummary == .mixed)
        #expect(media.prioritySummary == .high)
    }

    @Test func unknownStatsStayUnknownWithoutLosingProgressOrSize() throws {
        let root = TorrentFileTreeBuilder.build(
            rootName: "Partial metadata",
            entries: [
                entry(0, "Folder/one.bin", 100, 40, wanted: nil, priority: nil),
                entry(1, "Folder/two.bin", 200, 100, wanted: true, priority: 0)
            ]
        )
        let folder = try #require(root.children?.first)
        #expect(folder.length == 300)
        #expect(folder.bytesCompleted == 140)
        #expect(abs(folder.progress - (140.0 / 300.0)) < 0.000_001)
        #expect(folder.wantedSummary == .unknown)
        #expect(folder.prioritySummary == .unknown)
    }

    @Test func stripsTorrentRootPrefixAlreadyRepresentedByRootRow() {
        let root = TorrentFileTreeBuilder.build(
            rootName: "Original Microsoft Office 2019 x86_x64 RU",
            rootID: "torrent:99",
            entries: [
                entry(0, "Original Microsoft Office 2019 x86_x64 RU/Tabletka/MAS/setup.cmd",
                      100, 100),
                entry(1, "Original Microsoft Office 2019 x86_x64 RU/LICENSE",
                      20, 20)
            ]
        )
        #expect(root.children?.map(\.name) == ["Tabletka", "LICENSE"])
        #expect(root.children?.first?.children?.first?.name == "MAS")
        #expect(root.children?.first?.children?.first?.children?.first?.name == "setup.cmd")
        #expect(root.fileIndices == [0, 1])
    }

    @Test func singleFileTorrentNameIsNotMistakenForARootPathPrefix() {
        let root = TorrentFileTreeBuilder.build(
            rootName: "Ubuntu.iso",
            entries: [entry(0, "Ubuntu.iso", 100, 50)]
        )
        #expect(root.children?.count == 1)
        #expect(root.children?.first?.name == "Ubuntu.iso")
        #expect(root.children?.first?.fileIndex == 0)
    }

    @Test func emptyAndUnsafePathComponentsDoNotCreatePhantomDirectories() {
        let root = TorrentFileTreeBuilder.build(
            rootName: "Paths",
            entries: [
                entry(0, "/./../", 12, 12),
                entry(1, "///folder//file.txt", 20, 10)
            ]
        )
        #expect(root.children?.map(\.name) == ["folder", "File 1"])
        #expect(root.children?.last?.fileIndex == 0)
        #expect(root.fileIndices == [0, 1])
    }

    @Test func duplicateOrNegativeRPCIndicesAreIgnoredWithoutAliasingRows() {
        let root = TorrentFileTreeBuilder.build(
            rootName: "Duplicate metadata",
            entries: [
                entry(4, "Folder/first.txt", 10, 10),
                entry(4, "Folder/duplicate.txt", 20, 20),
                entry(-1, "Folder/negative.txt", 30, 30),
                entry(5, "Folder/second.txt", 40, 20)
            ]
        )
        let folder = root.children?.first
        #expect(folder?.fileIndices == [4, 5])
        #expect(folder?.children?.map(\.name) == ["first.txt", "second.txt"])
    }

    @Test func fileAndDirectoryWithSameDisplayNameRemainDistinct() {
        let root = TorrentFileTreeBuilder.build(
            rootName: "Collision",
            entries: [
                entry(0, "Data", 10, 10),
                entry(1, "Data/child.bin", 20, 10)
            ]
        )
        #expect(root.children?.map(\.name) == ["Data", "Data"])
        #expect(root.children?.map(\.isDirectory) == [true, false])
        #expect(root.children?.map(\.fileIndices) == [[1], [0]])
        #expect(Set(root.children?.map(\.id) ?? []).count == 2)
    }

    @Test func zeroLengthAndInvalidCountersAreBounded() {
        let root = TorrentFileTreeBuilder.build(
            rootName: "Bounds",
            entries: [
                entry(0, "empty.dat", 0, 0),
                entry(1, "oversized.dat", 10, 90),
                entry(2, "negative.dat", -10, -20)
            ]
        )
        #expect(root.length == 10)
        #expect(root.bytesCompleted == 10)
        #expect(root.children?.map(\.progress) == [1, 1, 1])
    }
}
