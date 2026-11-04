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
    @Environment(TreManaModel.self) private var model
    @Binding var isExpanded: Bool
    @Binding var selectedTab: InspectorTab
    @State private var peerSortOrder: [KeyPathComparator<InspectorPeerRow>] = [
        KeyPathComparator(\.downRate, order: .reverse)
    ]

    private var selectedID: Int? {
        guard model.selectedTorrentIDs.count == 1 else { return nil }
        return model.selectedTorrentIDs.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Picker("Torrent details", selection: $selectedTab) {
                    ForEach(InspectorTab.allCases) { tab in
                        Text(LocalizedStringKey(tab.rawValue)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 545)
                Spacer(minLength: 0)
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .help(LocalizedStringKey(isExpanded ? "Restore split view" : "Expand details"))
                .accessibilityLabel(LocalizedStringKey(isExpanded ? "Restore torrent list" : "Expand torrent details"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()

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
        let selectionAvailable = stats?.count == entries.count
        let wantedCount = stats?.filter(\.wanted).count ?? 0

        return VStack(spacing: 0) {
            if !entries.isEmpty {
                HStack(spacing: 8) {
                    Text("Files to download")
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 0)
                    if selectionAvailable {
                        Text("\(wantedCount) / \(entries.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if model.strictQueuePendingIDs.contains(detail.id) {
                        Label("Ordered download pending", systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if model.strictQueueTorrentIDs.contains(detail.id) {
                        Label("Ordered download active", systemImage: "list.number")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.top, 11)
                Text("File selection does not delete previously downloaded data.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 6)
            }
            if entries.isEmpty {
                placeholder("No file metadata available", symbol: "doc")
            } else {
                List {
                    ForEach(entries.indices, id: \.self) { index in
                        let file = entries[index]
                        let fileStats = selectionAvailable ? stats?[index] : nil
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(spacing: 9) {
                                Image(systemName: "doc")
                                    .foregroundStyle(.secondary)
                                Text(file.name)
                                    .font(.subheadline)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                                Spacer(minLength: 8)
                                Text(size(file.bytesCompleted) + " / " + size(file.length))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            ProgressView(value: completion(file.bytesCompleted, file.length))
                                .progressViewStyle(.linear)

                            if let fileStats {
                                HStack(spacing: 15) {
                                    Toggle("Download file", isOn: Binding(
                                        get: {
                                            guard let current = model.selectedTorrentDetail,
                                                  current.id == detail.id,
                                                  let currentStats = current.fileStats,
                                                  currentStats.indices.contains(index) else {
                                                return fileStats.wanted
                                            }
                                            return currentStats[index].wanted
                                        },
                                        set: { next in
                                            Task {
                                                await model.setFileWanted(
                                                    torrentID: detail.id,
                                                    fileIndex: index,
                                                    wanted: next,
                                                    expectedWanted: fileStats.wanted
                                                )
                                            }
                                        }
                                    ))
                                    .toggleStyle(.checkbox)
                                    .disabled(model.isBusy || model.strictQueueTorrentIDs.contains(detail.id) || (fileStats.wanted && wantedCount == 1))
                                    .help(LocalizedStringKey(
                                        model.strictQueueTorrentIDs.contains(detail.id)
                                            ? "Disable ordered downloading before changing file selection"
                                            : fileStats.wanted && wantedCount == 1
                                                ? "At least one file must remain selected for download"
                                                : "Include this file in the download"
                                    ))
                                    .accessibilityIdentifier("file.wanted.\(index)")

                                    Picker("Priority", selection: Binding(
                                        get: {
                                            guard let current = model.selectedTorrentDetail,
                                                  current.id == detail.id,
                                                  let currentStats = current.fileStats,
                                                  currentStats.indices.contains(index) else {
                                                return fileStats.priority
                                            }
                                            return currentStats[index].priority
                                        },
                                        set: { next in
                                            Task {
                                                await model.setFilePriority(
                                                    torrentID: detail.id,
                                                    fileIndex: index,
                                                    priority: next,
                                                    expectedPriority: fileStats.priority
                                                )
                                            }
                                        }
                                    )) {
                                        Text("Low").tag(-1)
                                        Text("Normal").tag(0)
                                        Text("High").tag(1)
                                    }
                                    .pickerStyle(.menu)
                                    .fixedSize()
                                    .disabled(model.isBusy)
                                    .accessibilityIdentifier("file.priority.\(index)")
                                    Spacer(minLength: 0)
                                }
                                .font(.caption)
                            } else {
                                Label("File selection unavailable", systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(.plain)
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
