import Foundation

public enum TorrentFileWantedSummary: Sendable, Equatable {
    case wanted
    case unwanted
    case mixed
    case unknown
}

/// One Transmission RPC file, retaining its original RPC index for safe mutations.
public struct TorrentFileTreeEntry: Sendable, Equatable {
    public let index: Int
    public let path: String
    public let length: Int64
    public let bytesCompleted: Int64
    public let wanted: Bool?
    public let priority: Int?

    public init(
        index: Int,
        path: String,
        length: Int64,
        bytesCompleted: Int64,
        wanted: Bool?,
        priority: Int?
    ) {
        self.index = index
        self.path = path
        self.length = length
        self.bytesCompleted = bytesCompleted
        self.wanted = wanted
        self.priority = priority
    }
}

/// Immutable presentation tree. Folder aggregates are derived from descendant
/// files; fileIndex always remains the original Transmission RPC index.
public struct TorrentFileTreeNode: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let relativePath: String
    public let depth: Int
    public let isDirectory: Bool
    public let fileIndex: Int?
    public let children: [TorrentFileTreeNode]?
    public let fileIndices: [Int]
    public let length: Int64
    public let bytesCompleted: Int64
    public let wantedSummary: TorrentFileWantedSummary
    public let wantedFileCount: Int
    public let prioritySummary: TorrentFilePrioritySummary

    public var fileCount: Int { fileIndices.count }

    public var progress: Double {
        guard length > 0 else { return 1 }
        return min(1, max(0, Double(bytesCompleted) / Double(length)))
    }
}

public enum TorrentFileTreeBuilder {
    private struct FileLeaf {
        let entry: TorrentFileTreeEntry
        let name: String
        let relativePath: String
    }

    private final class DirectoryBuilder {
        let name: String
        let relativePath: String
        var directoryOrder: [String] = []
        var directories: [String: DirectoryBuilder] = [:]
        var files: [FileLeaf] = []

        init(name: String, relativePath: String) {
            self.name = name
            self.relativePath = relativePath
        }
    }

    /// Folders are kept in first-seen torrent order, followed by files in their
    /// original RPC order. Invalid/duplicate RPC indices are ignored safely.
    public static func build(
        rootName: String,
        rootID: String = "root",
        entries: [TorrentFileTreeEntry]
    ) -> TorrentFileTreeNode {
        let root = DirectoryBuilder(
            name: rootName.isEmpty ? "Torrent" : rootName,
            relativePath: ""
        )
        var seenIndices = Set<Int>()

        for entry in entries {
            guard entry.index >= 0, seenIndices.insert(entry.index).inserted else {
                continue
            }

            let components = entry.path
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
                .filter { $0 != "." && $0 != ".." }
            var safeComponents = components
            // Some Transmission-compatible servers include the torrent root
            // in every file path. The tree already renders that root as row 1.
            if safeComponents.count > 1 && safeComponents.first == root.name {
                safeComponents.removeFirst()
            }
            if safeComponents.isEmpty { safeComponents = ["File \(entry.index + 1)"] }
            let fileName = safeComponents[safeComponents.count - 1]

            var parent = root
            for component in safeComponents.dropLast() {
                if parent.directories[component] == nil {
                    let path = parent.relativePath.isEmpty
                        ? component : "\(parent.relativePath)/\(component)"
                    parent.directories[component] = DirectoryBuilder(
                        name: component, relativePath: path
                    )
                    parent.directoryOrder.append(component)
                }
                guard let next = parent.directories[component] else { continue }
                parent = next
            }

            parent.files.append(FileLeaf(
                entry: entry,
                name: fileName,
                relativePath: safeComponents.joined(separator: "/")
            ))
        }

        return makeDirectory(root, id: rootID, depth: 0, rootID: rootID)
    }

    private static func makeDirectory(
        _ directory: DirectoryBuilder,
        id: String,
        depth: Int,
        rootID: String
    ) -> TorrentFileTreeNode {
        let folders = directory.directoryOrder.compactMap { key -> TorrentFileTreeNode? in
            guard let child = directory.directories[key] else { return nil }
            return makeDirectory(
                child,
                id: "\(rootID)|directory|\(child.relativePath)",
                depth: depth + 1,
                rootID: rootID
            )
        }
        let files = directory.files.map { makeFile($0, depth: depth + 1, rootID: rootID) }
        let children = folders + files
        let indices = children.flatMap(\.fileIndices).sorted()

        return TorrentFileTreeNode(
            id: id,
            name: directory.name,
            relativePath: directory.relativePath,
            depth: depth,
            isDirectory: true,
            fileIndex: nil,
            children: children,
            fileIndices: indices,
            length: saturatedSum(children.map(\.length)),
            bytesCompleted: saturatedSum(children.map(\.bytesCompleted)),
            wantedSummary: aggregateWanted(children),
            wantedFileCount: children.reduce(0) { $0 + $1.wantedFileCount },
            prioritySummary: aggregatePriority(children)
        )
    }

    private static func makeFile(
        _ leaf: FileLeaf,
        depth: Int,
        rootID: String
    ) -> TorrentFileTreeNode {
        let length = max(0, leaf.entry.length)
        let completed = min(length, max(0, leaf.entry.bytesCompleted))
        let wantedCount = leaf.entry.wanted == true ? 1 : 0
        let wantedSummary: TorrentFileWantedSummary
        switch leaf.entry.wanted {
        case .some(true): wantedSummary = .wanted
        case .some(false): wantedSummary = .unwanted
        case .none: wantedSummary = .unknown
        }

        return TorrentFileTreeNode(
            id: "\(rootID)|file|\(leaf.entry.index)",
            name: leaf.name,
            relativePath: leaf.relativePath,
            depth: depth,
            isDirectory: false,
            fileIndex: leaf.entry.index,
            children: nil,
            fileIndices: [leaf.entry.index],
            length: length,
            bytesCompleted: completed,
            wantedSummary: wantedSummary,
            wantedFileCount: wantedCount,
            prioritySummary: TorrentFilePrioritySummary(
                priorities: [leaf.entry.priority]
            )
        )
    }

    private static func aggregateWanted(
        _ nodes: [TorrentFileTreeNode]
    ) -> TorrentFileWantedSummary {
        guard !nodes.isEmpty,
              !nodes.contains(where: { $0.wantedSummary == .unknown }) else {
            return .unknown
        }
        if nodes.allSatisfy({ $0.wantedSummary == .wanted }) { return .wanted }
        if nodes.allSatisfy({ $0.wantedSummary == .unwanted }) { return .unwanted }
        return .mixed
    }

    private static func aggregatePriority(
        _ nodes: [TorrentFileTreeNode]
    ) -> TorrentFilePrioritySummary {
        guard !nodes.isEmpty,
              !nodes.contains(where: { $0.prioritySummary == .unknown }),
              let first = nodes.first?.prioritySummary else {
            return .unknown
        }
        return nodes.allSatisfy { $0.prioritySummary == first } ? first : .mixed
    }

    private static func saturatedSum(_ values: [Int64]) -> Int64 {
        values.reduce(Int64(0)) { partial, value in
            let (sum, overflow) = partial.addingReportingOverflow(value)
            return overflow ? Int64.max : sum
        }
    }
}
