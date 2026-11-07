import SwiftUI
import TreManaCore

enum InspectorTab: String, CaseIterable, Identifiable {
    case overview = "Details"
    case files = "Files"
    case trackers = "Trackers"
    case peers = "Peers"
    case webSeeds = "Web Seeds"

    var id: Self { self }
}

struct TorrentInspectorView: View {
    let model: TreManaModel
    @Binding var selectedTab: InspectorTab
    @State private var selectedFileNodeIDs: Set<String> = []
    @State private var expandedFileFolderIDs: Set<String> = []
    @State private var expandedTreeTorrentID: Int?
    @State private var peerSortOrder: [KeyPathComparator<InspectorPeerRow>] = [
        KeyPathComparator(\.downRate, order: .reverse)
    ]

    private var selectedID: Int? {
        guard model.selectedTorrentIDs.count == 1 else { return nil }
        return model.selectedTorrentIDs.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 3) {
                    if let selectedID,
                       let torrent = model.torrents.first(where: { $0.id == selectedID }) {
                        Text(torrent.name)
                            .font(.headline.weight(.medium))
                            .lineLimit(1)
                            .help(torrent.name)
                        Text(torrent.percentDone, format: .percent.precision(.fractionLength(1)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Torrent details")
                            .font(.headline)
                        Text("Select a torrent to view details")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            HStack {
                Picker("Torrent details", selection: $selectedTab) {
                    ForEach(InspectorTab.allCases) { tab in
                        Text(LocalizedStringKey(tab.rawValue)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 540)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            Divider().opacity(0.4)

            Group {
                if selectedID == nil {
                    ContentUnavailableView(
                        LocalizedStringKey(model.selectedTorrentIDs.isEmpty
                            ? "Select a torrent to view details"
                            : "Select a single torrent"),
                        systemImage: "square.split.2x1"
                    )
                } else if let detail = model.selectedTorrentDetail,
                          detail.id == selectedID {
                    inspectorContent(detail)
                } else if let message = model.detailErrorMessage {
                    ContentUnavailableView(
                        "Unable to load torrent details",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading torrent details…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: selectedID) { _, _ in
            selectedFileNodeIDs.removeAll()
            expandedFileFolderIDs.removeAll()
            expandedTreeTorrentID = nil
        }
        .task(id: selectedID) {
            await model.loadSelectedTorrentDetails()
            guard let id = selectedID else { return }
            while !Task.isCancelled && model.isConnected,
                  model.selectedTorrentIDs == Set([id]) {
                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    break
                }
                guard !Task.isCancelled, model.isConnected,
                      model.selectedTorrentIDs == Set([id]) else { break }
                await model.loadSelectedTorrentDetails()
            }
        }
    }

    @ViewBuilder
    private func inspectorContent(_ detail: TransmissionTorrentDetail) -> some View {
        switch selectedTab {
        case .overview:
            overview(detail)
        case .files:
            files(detail)
        case .trackers:
            trackers(detail)
        case .peers:
            peers(detail)
        case .webSeeds:
            webSeeds(detail)
        }
    }

    private func overview(_ detail: TransmissionTorrentDetail) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 260), alignment: .topLeading),
                    GridItem(.flexible(minimum: 260), alignment: .topLeading)
                ],
                alignment: .leading,
                spacing: 12
            ) {
                GroupBox("Activity") {
                    VStack(spacing: 7) {
                        InfoLine("Progress", detail.percentDone.map {
                            $0.formatted(.percent.precision(.fractionLength(1)))
                        } ?? "—")
                        InfoLine("Downloaded", size(detail.downloadedEver))
                        InfoLine("Uploaded", size(detail.uploadedEver))
                        InfoLine("Remaining", size(detail.leftUntilDone))
                        InfoLine("Download speed", rate(detail.rateDownload))
                        InfoLine("Upload speed", rate(detail.rateUpload))
                        InfoLine("Ratio", detail.uploadRatio.map {
                            $0.formatted(.number.precision(.fractionLength(2)))
                        } ?? "—")
                        InfoLine("ETA", eta(detail.eta))
                        InfoLine("Connected peers", detail.peersConnected.map(String.init) ?? "—")
                        InfoLine("Peers uploading", detail.peersSendingToUs.map(String.init) ?? "—")
                        InfoLine("Peers downloading", detail.peersGettingFromUs.map(String.init) ?? "—")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                GroupBox("Information") {
                    VStack(spacing: 7) {
                        InfoLine("Name", detail.name)
                        InfoLine("Size", size(detail.totalSize))
                        InfoLine("Selected size", size(detail.sizeWhenDone))
                        InfoLine("Location (server)", detail.downloadDir ?? "—")
                        InfoLine("Info hash", detail.hashString ?? "—")
                        InfoLine("Created by", detail.creator ?? "—")
                        InfoLine("Created", date(detail.dateCreated))
                        InfoLine("Added", date(detail.addedDate))
                        InfoLine("Completed", date(detail.doneDate))
                        InfoLine("Last activity", date(detail.activityDate))
                        InfoLine("Comment", detail.comment ?? "—")
                        if let error = detail.errorString, !error.isEmpty {
                            InfoLine("Transmission error", error)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
            .padding(12)
        }
    }

    private func files(_ detail: TransmissionTorrentDetail) -> some View {
        let entries = detail.files ?? []
        let stats = detail.fileStats
        let hasStats = stats?.count == entries.count
        let wantedCount = stats?.filter(\.wanted).count ?? 0
        let queueLocked = model.strictQueueTorrentIDs.contains(detail.id)
        let fileRows = entries.indices.map { FileTableEntry(
            id: $0, file: entries[$0], stat: hasStats ? stats?[$0] : nil
        ) }
        let fileRowsByIndex = Dictionary(uniqueKeysWithValues: fileRows.map { ($0.id, $0) })
        let treeEntries = entries.indices.map { index in
            TorrentFileTreeEntry(
                index: index,
                path: entries[index].name,
                length: entries[index].length,
                bytesCompleted: entries[index].bytesCompleted,
                wanted: hasStats ? stats?[index].wanted : nil,
                priority: hasStats ? stats?[index].priority : nil
            )
        }
        let root = TorrentFileTreeBuilder.build(
            rootName: detail.name,
            rootID: "torrent:\(detail.id)",
            entries: treeEntries
        )
        let allNodes = allFileTreeNodes(root)
        let nodeByID = Dictionary(uniqueKeysWithValues: allNodes.map { ($0.id, $0) })
        let visibleRows = visibleFileTreeRows(root)
        let selectedIndices = Set(selectedFileNodeIDs
            .compactMap { nodeByID[$0] }
            .flatMap(\.fileIndices))
        let selectedCount = selectedIndices.count

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("\(wantedCount) / \(entries.count)")
                    .monospacedDigit()
                Text("Files selected")
                if selectedCount > 0 {
                    Text("·")
                    Text("Selected")
                    Text(selectedCount, format: .number).monospacedDigit()
                }
                Spacer(minLength: 0)
                Button {
                    expandedFileFolderIDs = Set(allNodes
                        .filter(\.isDirectory)
                        .map(\.id))
                } label: {
                    Image(systemName: "chevron.down.square")
                }
                .buttonStyle(.plain)
                .help("Expand all folders")
                .accessibilityLabel("Expand all folders")
                Button {
                    expandedFileFolderIDs.removeAll()
                } label: {
                    Image(systemName: "chevron.up.square")
                }
                .buttonStyle(.plain)
                .help("Collapse all folders")
                .accessibilityLabel("Collapse all folders")
                if model.strictQueuePendingIDs.contains(detail.id) {
                    Label("Ordered download pending", systemImage: "clock")
                } else if queueLocked {
                    Label("Ordered download active", systemImage: "list.number")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 15)
            .padding(.vertical, 7)

            if entries.isEmpty {
                placeholder("No file metadata available", symbol: "doc")
            } else {
                Table(visibleRows, selection: $selectedFileNodeIDs) {
                    TableColumn("Name") { row in
                        fileTreeNameCell(row)
                    }
                    .width(min: 220, ideal: 430)
                    .customizationID("files.name")

                    TableColumn("Size") { row in
                        Text(size(row.node.length))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .width(min: 74, ideal: 94)
                    .customizationID("files.size")

                    TableColumn("Progress") { row in
                        HStack(spacing: 7) {
                            ProgressView(value: row.node.progress)
                            Text(row.node.progress, format: .percent.precision(.fractionLength(1)))
                                .font(.caption.monospacedDigit())
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                    .width(min: 100, ideal: 155)
                    .customizationID("files.progress")

                    TableColumn("Download file") { row in
                        if let fileIndex = row.node.fileIndex,
                           let fileRow = fileRowsByIndex[fileIndex] {
                            FileWantedCell(model: model,
                                           torrentID: detail.id, row: fileRow,
                                           wantedCount: wantedCount, queueLocked: queueLocked)
                                .equatable()
                        } else {
                            FileTreeWantedCell(
                                model: model, torrentID: detail.id, node: row.node,
                                wantedCount: wantedCount, queueLocked: queueLocked
                            )
                            .equatable()
                        }
                    }
                    .width(min: 72, ideal: 90)
                    .customizationID("files.download")

                    TableColumn("Priority") { row in
                        if let fileIndex = row.node.fileIndex,
                           let fileRow = fileRowsByIndex[fileIndex] {
                            FilePriorityCell(model: model,
                                             torrentID: detail.id, row: fileRow)
                                .equatable()
                        } else {
                            FileTreePriorityCell(
                                model: model, torrentID: detail.id, node: row.node
                            )
                            .equatable()
                        }
                    }
                    .width(min: 100, ideal: 130)
                    .customizationID("files.priority")
                }
                .contextMenu(forSelectionType: String.self) { clicked in
                    let chosen = Set(clicked
                        .compactMap { nodeByID[$0] }
                        .flatMap(\.fileIndices))
                        .sorted()
                    if !chosen.isEmpty && hasStats {
                        FileBatchActions(
                            model: model,
                            torrentID: detail.id,
                            indices: chosen,
                            wantedCount: wantedCount,
                            selectedWantedCount: chosen.filter {
                                stats?[$0].wanted == true
                            }.count,
                            queueLocked: queueLocked
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Block interaction during an RPC without dimming every cell.
                .allowsHitTesting(!model.isBusy)
                .background(alignment: .topLeading) {
                    TableColumnWidthPersistence(
                        tableIdentifier: "files",
                        columnIdentifiers: [
                            "files.name", "files.size", "files.progress",
                            "files.download", "files.priority"
                        ],
                        titleIdentifiers: TableColumnWidthPersistence.fileTitleIdentifiers
                    )
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .accessibilityIdentifier("files.table")
                .onAppear {
                    if expandedTreeTorrentID != detail.id {
                        expandedTreeTorrentID = detail.id
                        selectedFileNodeIDs.removeAll()
                        expandedFileFolderIDs = defaultExpandedFolderIDs(
                            root, totalFileCount: entries.count
                        )
                    }
                }
            }
        }
    }

    private func allFileTreeNodes(
        _ root: TorrentFileTreeNode
    ) -> [TorrentFileTreeNode] {
        var result: [TorrentFileTreeNode] = []
        func visit(_ node: TorrentFileTreeNode) {
            result.append(node)
            for child in node.children ?? [] { visit(child) }
        }
        visit(root)
        return result
    }

    private func visibleFileTreeRows(
        _ root: TorrentFileTreeNode
    ) -> [FileTreeTableRow] {
        var result: [FileTreeTableRow] = []
        func visit(_ node: TorrentFileTreeNode, depth: Int) {
            result.append(FileTreeTableRow(node: node, depth: depth))
            guard expandedFileFolderIDs.contains(node.id) else { return }
            for child in node.children ?? [] { visit(child, depth: depth + 1) }
        }
        visit(root, depth: 0)
        return result
    }

    private func defaultExpandedFolderIDs(
        _ root: TorrentFileTreeNode,
        totalFileCount: Int
    ) -> Set<String> {
        var result = Set<String>()
        let expandAll = totalFileCount <= 60
        func visit(_ node: TorrentFileTreeNode, depth: Int) {
            guard node.isDirectory, !(node.children ?? []).isEmpty else { return }
            if expandAll || depth < 2 {
                result.insert(node.id)
                for child in node.children ?? [] { visit(child, depth: depth + 1) }
            }
        }
        visit(root, depth: 0)
        return result
    }

    private func fileTreeNameCell(_ row: FileTreeTableRow) -> some View {
        HStack(spacing: 6) {
            if row.node.isDirectory {
                Button {
                    if expandedFileFolderIDs.contains(row.node.id) {
                        expandedFileFolderIDs.remove(row.node.id)
                    } else {
                        expandedFileFolderIDs.insert(row.node.id)
                    }
                } label: {
                    Image(systemName: expandedFileFolderIDs.contains(row.node.id)
                        ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 13, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled((row.node.children ?? []).isEmpty)
                .help(expandedFileFolderIDs.contains(row.node.id)
                    ? "Collapse folder" : "Expand folder")
            } else {
                Color.clear.frame(width: 13, height: 20)
            }

            Image(systemName: fileTreeSymbol(for: row.node))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(row.node.isDirectory ? Color.accentColor : Color.secondary)
                .frame(width: 17)

            Text(row.node.name)
                .font(row.depth == 0
                    ? .body.weight(.semibold)
                    : row.node.isDirectory ? .body.weight(.medium) : .body)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(row.node.relativePath.isEmpty
                    ? row.node.name : row.node.relativePath)
        }
        .padding(.leading, CGFloat(row.depth) * 15)
        .contentShape(Rectangle())
    }

    private func fileTreeSymbol(for node: TorrentFileTreeNode) -> String {
        if node.isDirectory {
            return node.depth == 0 ? "externaldrive.fill" : "folder.fill"
        }
        return switch URL(fileURLWithPath: node.name).pathExtension.lowercased() {
        case "app", "pkg": "app"
        case "zip", "7z", "rar", "tar", "gz", "dmg", "iso": "archivebox"
        case "pdf": "doc.richtext"
        case "md", "txt", "rtf", "html", "htm": "doc.text"
        case "cmd", "bat", "sh", "ps1", "command": "terminal"
        case "jpg", "jpeg", "png", "gif", "heic", "webp": "photo"
        case "mp3", "m4a", "wav", "flac", "aac": "music.note"
        case "mp4", "mov", "mkv", "avi": "film"
        default: "doc"
        }
    }

    private func trackers(_ detail: TransmissionTorrentDetail) -> some View {
        let stats = detail.trackerStats ?? []
        let configured = detail.trackers ?? []
        return Group {
            if !stats.isEmpty {
                List {
                    ForEach(stats.indices, id: \.self) { index in
                        let stat = stats[index]
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(stat.host ?? stat.announce ?? "Tracker")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    if let announce = stat.announce {
                                        Text(announce)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .help(announce)
                                            .textSelection(.enabled)
                                    }
                                }
                                Spacer(minLength: 8)
                                Text("Seeds \(stat.seederCount.map(String.init) ?? "—")")
                                Text("Leechers \(stat.leecherCount.map(String.init) ?? "—")")
                                Text("Peers \(stat.lastAnnouncePeerCount.map(String.init) ?? "—")")
                            }
                            HStack(spacing: 10) {
                                Label(LocalizedStringKey(announceStatus(stat)), systemImage: announceIcon(stat))
                                    .foregroundStyle(stat.lastAnnounceSucceeded == false
                                        ? Color.orange : Color.secondary)
                                Text("Last \(date(stat.lastAnnounceTime))")
                                Text("Next \(date(stat.nextAnnounceTime))")
                                if let tier = stat.tier {
                                    Text("Tier \(tier)")
                                }
                                Spacer(minLength: 0)
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            if let result = stat.lastAnnounceResult, !result.isEmpty,
                               result.lowercased() != "success" {
                                Text(result)
                                    .font(.caption2)
                                    .foregroundStyle(stat.lastAnnounceSucceeded == false
                                        ? Color.orange : Color.secondary)
                                    .textSelection(.enabled)
                            }
                            if let scrape = stat.lastScrapeResult, !scrape.isEmpty,
                               scrape.lowercased() != "success" {
                                Text("Scrape: \(scrape)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.plain)
            } else if !configured.isEmpty {
                List {
                    ForEach(configured.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(configured[index].announce ?? "Tracker")
                                .font(.subheadline)
                                .textSelection(.enabled)
                            if let tier = configured[index].tier {
                                Text("Tier \(tier) · No announce statistics yet")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            } else {
                placeholder("No trackers reported", symbol: "network")
            }
        }
    }

    private func announceStatus(_ stat: TransmissionTorrentTrackerStat) -> String {
        if stat.lastAnnounceTimedOut == true { return "Timed out" }
        if stat.lastAnnounceSucceeded == true { return "Announced" }
        if stat.lastAnnounceSucceeded == false && stat.hasAnnounced == true {
            return "Announce failed"
        }
        if stat.hasAnnounced == true { return "Announced" }
        return "Not announced"
    }

    private func announceIcon(_ stat: TransmissionTorrentTrackerStat) -> String {
        if stat.lastAnnounceTimedOut == true || stat.lastAnnounceSucceeded == false {
            return "exclamationmark.triangle"
        }
        if stat.lastAnnounceSucceeded == true { return "checkmark.circle" }
        return "clock"
    }

    private func peers(_ detail: TransmissionTorrentDetail) -> some View {
        let rows: [InspectorPeerRow] = (detail.peers ?? []).enumerated().map {
            index, peer in
            InspectorPeerRow(
                id: index,
                address: peer.address + (peer.port.map { ":\($0)" } ?? ""),
                client: peer.clientName ?? "Unknown",
                progress: peer.progress ?? -1,
                downRate: peer.rateToClient ?? 0,
                upRate: peer.rateToPeer ?? 0
            )
        }
        return Group {
            if rows.isEmpty {
                placeholder("No connected peers", symbol: "person.2")
            } else {
                Table(rows.sorted(using: peerSortOrder), sortOrder: $peerSortOrder) {
                    TableColumn("Address", value: \.address)
                    TableColumn("Client", value: \.client)
                    TableColumn("Progress", value: \.progress) { row in
                        Text(row.progress >= 0
                            ? row.progress.formatted(.percent.precision(.fractionLength(0)))
                            : "—")
                            .monospacedDigit()
                    }
                    TableColumn("↓ Download", value: \.downRate) { row in
                        Text(rate(row.downRate)).monospacedDigit()
                    }
                    TableColumn("↑ Upload", value: \.upRate) { row in
                        Text(rate(row.upRate)).monospacedDigit()
                    }
                }
                .alternatingRowBackgrounds(.disabled)
                .accessibilityLabel("Peers; click a column header to sort")
            }
        }
    }

    private func webSeeds(_ detail: TransmissionTorrentDetail) -> some View {
        let entries = detail.webseeds ?? []
        return VStack(spacing: 0) {
            Text("HTTP/HTTPS mirrors that supply torrent pieces alongside regular peers.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            Divider()
            if entries.isEmpty {
                placeholder("This torrent has no web seeds", symbol: "network")
            } else {
                List {
                    ForEach(entries.indices, id: \.self) { index in
                        Text(entries[index])
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func placeholder(_ message: String, symbol: String) -> some View {
        ContentUnavailableView(LocalizedStringKey(message), systemImage: symbol)
    }

    private func size(_ bytes: Int64?) -> String {
        guard let bytes, bytes >= 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }

    private func rate(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        return size(bytes) + "/s"
    }

    private func eta(_ value: Int?) -> String {
        guard let value, value >= 0 else { return "—" }
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m \(value % 60)s"
    }

    private func date(_ timestamp: Int?) -> String {
        guard let timestamp, timestamp > 0 else { return "—" }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
            .formatted(date: .abbreviated, time: .shortened)
    }

    private func completion(_ completed: Int64, _ total: Int64) -> Double {
        guard total > 0 else { return 1 }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}


private struct FileTreeTableRow: Identifiable {
    let node: TorrentFileTreeNode
    let depth: Int

    var id: String { node.id }
}

private enum FileWantedControlState: Equatable {
    case selected
    case unselected
    case mixed
    case unknown

    init(_ summary: TorrentFileWantedSummary) {
        switch summary {
        case .wanted: self = .selected
        case .unwanted: self = .unselected
        case .mixed: self = .mixed
        case .unknown: self = .unknown
        }
    }

    var accessibilityValue: LocalizedStringKey {
        switch self {
        case .selected: "Selected"
        case .unselected: "Not selected"
        case .mixed: "Mixed"
        case .unknown: "Unknown"
        }
    }
}

/// A single, deliberately drawn control for file and folder selection.
/// Unlike the platform checkbox, its geometry and accent color do not change
/// when the main window loses key-window focus.
private struct FileWantedControl: View {
    let state: FileWantedControlState
    let title: LocalizedStringKey
    let help: LocalizedStringKey
    let identifier: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(fillColor)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)

                switch state {
                case .selected:
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white)
                case .mixed:
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 2)
                case .unselected:
                    EmptyView()
                case .unknown:
                    Image(systemName: "minus")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                }
            }
            .frame(width: 17, height: 17)
            .frame(width: 32, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || state == .unknown)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityValue(Text(state.accessibilityValue))
        .accessibilityIdentifier(identifier)
    }

    private var fillColor: Color {
        switch state {
        case .selected: Color.accentColor
        case .mixed: Color.accentColor.opacity(0.14)
        case .unselected, .unknown: Color.primary.opacity(0.035)
        }
    }

    private var borderColor: Color {
        switch state {
        case .selected, .mixed: Color.accentColor
        case .unselected: Color.secondary.opacity(0.55)
        case .unknown: Color.secondary.opacity(0.35)
        }
    }
}

private struct FileTreeWantedCell: View, Equatable {
    let model: TreManaModel
    let torrentID: Int
    let node: TorrentFileTreeNode
    let wantedCount: Int
    let queueLocked: Bool

    private var shouldDownload: Bool {
        node.wantedSummary != .wanted
    }

    private var actionTitle: String {
        shouldDownload ? "Download folder contents" : "Skip folder contents"
    }

    private var canChangeSelection: Bool {
        !queueLocked &&
            node.wantedSummary != .unknown &&
            !node.fileIndices.isEmpty &&
            (shouldDownload || wantedCount > node.wantedFileCount)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model &&
        lhs.torrentID == rhs.torrentID &&
        lhs.node.id == rhs.node.id &&
        lhs.node.wantedSummary == rhs.node.wantedSummary &&
        lhs.node.wantedFileCount == rhs.node.wantedFileCount &&
        lhs.node.fileIndices == rhs.node.fileIndices &&
        lhs.queueLocked == rhs.queueLocked &&
        lhs.canChangeSelection == rhs.canChangeSelection
    }

    var body: some View {
        FileWantedControl(
            state: FileWantedControlState(node.wantedSummary),
            title: LocalizedStringKey(actionTitle),
            help: LocalizedStringKey(
                node.wantedSummary == .mixed ? "Partially selected" : actionTitle
            ),
            identifier: "folder.wanted.\(node.id)",
            isEnabled: canChangeSelection
        ) {
            guard !node.fileIndices.isEmpty else { return }
            Task {
                await model.applyFileBatch(
                    torrentID: torrentID,
                    indices: node.fileIndices,
                    action: .download(shouldDownload)
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FileTreePriorityCell: View, Equatable {
    let model: TreManaModel
    let torrentID: Int
    let node: TorrentFileTreeNode

    private var selection: Int {
        switch node.prioritySummary {
        case .low: -1
        case .normal: 0
        case .high: 1
        case .mixed: 2
        case .skipped: 3
        case .unknown: 4
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model &&
        lhs.torrentID == rhs.torrentID &&
        lhs.node.id == rhs.node.id &&
        lhs.node.fileIndices == rhs.node.fileIndices &&
        lhs.node.prioritySummary == rhs.node.prioritySummary
    }

    var body: some View {
        Group {
            if node.prioritySummary == .unknown {
                Text("—")
                    .foregroundStyle(.tertiary)
            } else if node.prioritySummary == .skipped {
                Text("Skipped")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("folder.priority.skipped.\(node.id)")
            } else {
                Picker("Priority", selection: Binding(
                    get: { selection },
                    set: { value in
                        guard (-1...1).contains(value) else { return }
                        Task {
                            await model.applyFileBatch(
                                torrentID: torrentID,
                                indices: node.fileIndices,
                                action: .priority(value)
                            )
                        }
                    }
                )) {
                    Text("Low").tag(-1)
                    Text("Normal").tag(0)
                    Text("High").tag(1)
                    if node.prioritySummary == .mixed {
                        Text("Mixed").tag(2)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(node.fileIndices.isEmpty)
                .accessibilityIdentifier("folder.priority.\(node.id)")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FileTableEntry: Identifiable {
    let id: Int
    let file: TransmissionTorrentFile
    let stat: TransmissionTorrentFileStat?

    var progress: Double {
        guard file.length > 0 else { return 1 }
        return min(1, max(0, Double(file.bytesCompleted) / Double(file.length)))
    }
}

private struct FileWantedCell: View, Equatable {
    let model: TreManaModel
    let torrentID: Int
    let row: FileTableEntry
    let wantedCount: Int
    let queueLocked: Bool

    private var wanted: Bool { row.stat?.wanted ?? false }
    private var hasStats: Bool { row.stat != nil }
    private var canChangeSelection: Bool {
        hasStats && !queueLocked && (!wanted || wantedCount > 1)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model &&
        lhs.torrentID == rhs.torrentID &&
        lhs.row.id == rhs.row.id &&
        lhs.hasStats == rhs.hasStats &&
        lhs.wanted == rhs.wanted &&
        lhs.canChangeSelection == rhs.canChangeSelection
    }

    var body: some View {
        Group {
            if row.stat != nil {
                FileWantedControl(
                    state: wanted ? .selected : .unselected,
                    title: "Download file",
                    help: queueLocked
                        ? "Disable ordered downloading before changing file selection"
                        : "Download file",
                    identifier: "file.wanted.\(row.id)",
                    isEnabled: canChangeSelection
                ) {
                    let previous = wanted
                    Task {
                        await model.setFileWanted(
                            torrentID: torrentID,
                            fileIndex: row.id,
                            wanted: !previous,
                            expectedWanted: previous
                        )
                    }
                }
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FilePriorityCell: View, Equatable {
    let model: TreManaModel
    let torrentID: Int
    let row: FileTableEntry

    private var priority: Int { row.stat?.priority ?? 0 }
    private var wanted: Bool { row.stat?.wanted ?? false }
    private var hasStats: Bool { row.stat != nil }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model &&
        lhs.torrentID == rhs.torrentID &&
        lhs.row.id == rhs.row.id &&
        lhs.hasStats == rhs.hasStats &&
        lhs.wanted == rhs.wanted &&
        lhs.priority == rhs.priority
    }

    var body: some View {
        Group {
            if hasStats && !wanted {
                Text("Skipped")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("file.priority.skipped.\(row.id)")
            } else if hasStats {
                Picker("Priority", selection: Binding(
                    get: { priority },
                    set: { value in
                        let previous = priority
                        Task {
                            await model.setFilePriority(
                                torrentID: torrentID, fileIndex: row.id,
                                priority: value, expectedPriority: previous
                            )
                        }
                    }
                )) {
                    Text("Low").tag(-1)
                    Text("Normal").tag(0)
                    Text("High").tag(1)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityIdentifier("file.priority.\(row.id)")
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FileBatchActions: View {
    let model: TreManaModel
    let torrentID: Int
    let indices: [Int]
    let wantedCount: Int
    let selectedWantedCount: Int
    let queueLocked: Bool

    // Presented by Table's native selection context menu, not a separate toolbar.
    // The indices come from the context selection, never all files by default.
    var body: some View {
        Group {
            Button("Download selected") { apply(.download(true)) }
                .disabled(queueLocked || model.isBusy)
            Button("Skip selected") { apply(.download(false)) }
                .disabled(queueLocked || model.isBusy || selectedWantedCount >= wantedCount)
            Divider()
            Button("Low priority") { apply(.priority(-1)) }
                .disabled(model.isBusy)
            Button("Normal priority") { apply(.priority(0)) }
                .disabled(model.isBusy)
            Button("High priority") { apply(.priority(1)) }
                .disabled(model.isBusy)
        }
    }

    private func apply(_ action: FileBatchAction) {
        guard !indices.isEmpty else { return }
        Task {
            await model.applyFileBatch(
                torrentID: torrentID, indices: indices, action: action
            )
        }
    }
}

private struct InspectorPeerRow: Identifiable {
    let id: Int
    let address: String
    let client: String
    let progress: Double
    let downRate: Int64
    let upRate: Int64
}

private struct InfoLine: View {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(LocalizedStringKey(title))
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .trailing)
            Text(value)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
    }
}
