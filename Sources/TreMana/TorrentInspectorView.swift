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
    @State private var selectedFileIndices: Set<Int> = []
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
        .onChange(of: selectedID) { _, _ in selectedFileIndices.removeAll() }
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
        let rows = entries.indices.map { FileTableEntry(
            id: $0, file: entries[$0], stat: hasStats ? stats?[$0] : nil
        ) }
        let selection = selectedFileIndices.filter { entries.indices.contains($0) }.sorted()

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("\(wantedCount) / \(entries.count)")
                    .monospacedDigit()
                Text("Files selected")
                if !selection.isEmpty {
                    Text("·")
                    Text("Selected")
                    Text(selection.count, format: .number).monospacedDigit()
                }
                Spacer(minLength: 0)
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

            if rows.isEmpty {
                placeholder("No file metadata available", symbol: "doc")
            } else {
                Table(rows, selection: $selectedFileIndices) {
                    TableColumn("Name") { row in
                        Label(row.file.name, systemImage: "doc")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(row.file.name)
                    }
                    .width(min: 190, ideal: 400)

                    TableColumn("Size") { row in
                        Text(size(row.file.length))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .width(min: 74, ideal: 94)

                    TableColumn("Progress") { row in
                        HStack(spacing: 7) {
                            ProgressView(value: row.progress)
                            Text(row.progress, format: .percent.precision(.fractionLength(1)))
                                .font(.caption.monospacedDigit())
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                    .width(min: 100, ideal: 155)

                    TableColumn("Download file") { row in
                        FileWantedCell(model: model, torrentID: detail.id, row: row,
                                       wantedCount: wantedCount, queueLocked: queueLocked)
                    }
                    .width(min: 72, ideal: 90)

                    TableColumn("Priority") { row in
                        FilePriorityCell(model: model, torrentID: detail.id, row: row)
                    }
                    .width(min: 100, ideal: 130)
                }
                .contextMenu(forSelectionType: Int.self) { clicked in
                    let chosen = clicked.filter { entries.indices.contains($0) }.sorted()
                    if !chosen.isEmpty && hasStats {
                        FileBatchActions(
                            model: model,
                            torrentID: detail.id,
                            indices: chosen,
                            wantedCount: wantedCount,
                            selectedWantedCount: chosen.filter { stats?[$0].wanted == true }.count,
                            queueLocked: queueLocked
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("files.table")
            }
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


private struct FileTableEntry: Identifiable {
    let id: Int
    let file: TransmissionTorrentFile
    let stat: TransmissionTorrentFileStat?

    var progress: Double {
        guard file.length > 0 else { return 1 }
        return min(1, max(0, Double(file.bytesCompleted) / Double(file.length)))
    }
}

private struct FileWantedCell: View {
    let model: TreManaModel
    let torrentID: Int
    let row: FileTableEntry
    let wantedCount: Int
    let queueLocked: Bool

    private var wanted: Bool {
        guard let detail = model.selectedTorrentDetail, detail.id == torrentID,
              let stats = detail.fileStats, stats.indices.contains(row.id) else {
            return row.stat?.wanted ?? false
        }
        return stats[row.id].wanted
    }

    var body: some View {
        Group {
            if row.stat != nil {
                Toggle("Download file", isOn: Binding(
                    get: { wanted },
                    set: { next in
                        let previous = wanted
                        Task {
                            await model.setFileWanted(
                                torrentID: torrentID, fileIndex: row.id,
                                wanted: next, expectedWanted: previous
                            )
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(model.isBusy || queueLocked || (wanted && wantedCount == 1))
                .help(queueLocked
                    ? "Disable ordered downloading before changing file selection"
                    : "Download file")
                .accessibilityIdentifier("file.wanted.\(row.id)")
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FilePriorityCell: View {
    let model: TreManaModel
    let torrentID: Int
    let row: FileTableEntry

    private var priority: Int {
        guard let detail = model.selectedTorrentDetail, detail.id == torrentID,
              let stats = detail.fileStats, stats.indices.contains(row.id) else {
            return row.stat?.priority ?? 0
        }
        return stats[row.id].priority
    }

    var body: some View {
        Group {
            if row.stat != nil {
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
                .disabled(model.isBusy)
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
