import SwiftUI
import TreManaCore

private enum InspectorTab: String, CaseIterable, Identifiable {
    case overview = "Details"
    case files = "Files"
    case trackers = "Trackers"
    case peers = "Peers"
    case webSeeds = "Web Seeds"
    case limits = "Limits"

    var id: Self { self }
}

struct TorrentInspectorView: View {
    @Environment(TreManaModel.self) private var model
    @State private var selectedTab: InspectorTab = .overview

    private var selectedID: Int? {
        guard model.selectedTorrentIDs.count == 1 else { return nil }
        return model.selectedTorrentIDs.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("TORRENT DETAILS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Torrent details", selection: $selectedTab) {
                    ForEach(InspectorTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 710)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            Divider()

            Group {
                if selectedID == nil {
                    ContentUnavailableView(
                        model.selectedTorrentIDs.isEmpty
                            ? "Select a torrent to view details"
                            : "Select a single torrent",
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
        case .limits:
            limits(detail)
        }
    }

    private func overview(_ detail: TransmissionTorrentDetail) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 240), alignment: .topLeading),
                    GridItem(.flexible(minimum: 240), alignment: .topLeading)
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
                    .padding(.vertical, 5)
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
                    .padding(.vertical, 5)
                }
            }
            .padding(12)
        }
    }

    private func files(_ detail: TransmissionTorrentDetail) -> some View {
        let entries = detail.files ?? []
        return Group {
            if entries.isEmpty {
                placeholder("No file metadata available", symbol: "doc")
            } else {
                List {
                    ForEach(entries.indices, id: \.self) { index in
                        let file = entries[index]
                        let wanted = detail.fileStats?.indices.contains(index) == true
                            ? detail.fileStats?[index].wanted : nil
                        HStack(spacing: 12) {
                            Image(systemName: wanted == false ? "minus.circle" : "doc")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(file.name)
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                                ProgressView(value: completion(file.bytesCompleted, file.length))
                                    .progressViewStyle(.linear)
                            }
                            Spacer(minLength: 8)
                            Text(size(file.bytesCompleted))
                                .monospacedDigit()
                            Text("/ " + size(file.length))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Text(wanted.map { $0 ? "Wanted" : "Skipped" } ?? "Unknown")
                                .foregroundStyle(.secondary)
                                .frame(width: 64, alignment: .trailing)
                        }
                        .font(.caption)
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
                            Text(stat.host ?? stat.announce ?? "Tracker")
                                .font(.subheadline.weight(.medium))
                            Text(stat.announce ?? "—")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Text("Seeders: \(stat.seederCount.map(String.init) ?? "—")  ·  Leechers: \(stat.leecherCount.map(String.init) ?? "—")  ·  \(stat.lastAnnounceResult ?? "No announcement result")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            } else if !configured.isEmpty {
                List {
                    ForEach(configured.indices, id: \.self) { index in
                        Text(configured[index].announce ?? "Tracker")
                            .textSelection(.enabled)
                    }
                }
                .listStyle(.plain)
            } else {
                placeholder("No trackers reported", symbol: "point.3.connected.trianglepath.dotted")
            }
        }
    }

    private func peers(_ detail: TransmissionTorrentDetail) -> some View {
        let entries = detail.peers ?? []
        return Group {
            if entries.isEmpty {
                placeholder("No connected peers", symbol: "person.2")
            } else {
                List {
                    ForEach(entries.indices, id: \.self) { index in
                        let peer = entries[index]
                        HStack(spacing: 14) {
                            Text(peer.address + (peer.port.map { ":\($0)" } ?? ""))
                                .frame(minWidth: 170, alignment: .leading)
                                .textSelection(.enabled)
                            Text(peer.clientName ?? "Unknown client")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 5)
                            Text(peer.progress.map {
                                $0.formatted(.percent.precision(.fractionLength(0)))
                            } ?? "—")
                                .monospacedDigit()
                            Text("↓ " + rate(peer.rateToClient))
                                .monospacedDigit()
                            Text("↑ " + rate(peer.rateToPeer))
                                .monospacedDigit()
                        }
                        .font(.caption)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func webSeeds(_ detail: TransmissionTorrentDetail) -> some View {
        let entries = detail.webseeds ?? []
        return Group {
            if entries.isEmpty {
                placeholder("No web seeds reported", symbol: "network")
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

    private func limits(_ detail: TransmissionTorrentDetail) -> some View {
        ScrollView {
            GroupBox("Torrent limits (read-only)") {
                VStack(spacing: 9) {
                    InfoLine("Download", limit(detail.downloadLimited, detail.downloadLimit))
                    InfoLine("Upload", limit(detail.uploadLimited, detail.uploadLimit))
                    InfoLine("Honor session limits", detail.honorsSessionLimits.map {
                        $0 ? "Yes" : "No"
                    } ?? "Unknown")
                    Text("Editing torrent limits will be added separately. These values are read from Transmission.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
            }
            .padding(12)
        }
    }

    private func placeholder(_ message: String, symbol: String) -> some View {
        ContentUnavailableView(message, systemImage: symbol)
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

    private func limit(_ enabled: Bool?, _ value: Int?) -> String {
        guard let enabled else { return "Unknown" }
        if !enabled { return "Unlimited" }
        return value.map { "\($0) KB/s" } ?? "Unknown"
    }

    private func completion(_ completed: Int64, _ total: Int64) -> Double {
        guard total > 0 else { return 1 }
        return min(1, max(0, Double(completed) / Double(total)))
    }
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
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .trailing)
            Text(value)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
    }
}
