import SwiftUI
import TreManaCore

enum TorrentColumn: String, CaseIterable, Identifiable {
    case name, progress, status, download, upload
    case seeds, leeches, eta, ratio, addedDate, totalSize
    case downloaded, uploaded, remaining, connectedPeers, queuePosition, priority

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "Name"
        case .progress: "Progress"
        case .status: "Status"
        case .download: "Download"
        case .upload: "Upload"
        case .seeds: "Seeds"
        case .leeches: "Leeches"
        case .eta: "ETA"
        case .ratio: "Ratio"
        case .addedDate: "Added"
        case .totalSize: "Total Size"
        case .downloaded: "Downloaded"
        case .uploaded: "Uploaded"
        case .remaining: "Remaining"
        case .connectedPeers: "Connected Peers"
        case .queuePosition: "Queue"
        case .priority: "Priority"
        }
    }

    var visibleByDefault: Bool {
        switch self {
        case .name, .totalSize, .progress, .download, .upload,
             .eta, .ratio, .priority: true
        default: false
        }
    }
}

struct TorrentColumnCell: View {
    let column: TorrentColumn
    let torrent: TransmissionTorrent
    let swarm: TorrentSwarmCounts?

    var body: some View {
        Group {
            switch column {
            case .name:
                HStack(spacing: 7) {
                    Image(systemName: iconName)
                        .foregroundStyle(iconColor)
                        .frame(width: 17)
                    Text(torrent.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(torrent.name)
                }
            case .progress:
                TorrentProgressCell(progress: torrent.percentDone)
            case .status:
                TorrentStatusCell(status: torrent.status)
            case .download:
                TransferRateCell(bytesPerSecond: torrent.rateDownload)
            case .upload:
                TransferRateCell(bytesPerSecond: torrent.rateUpload)
            case .seeds:
                metric(swarm?.seeds)
                    .help("Tracker-reported seeds (max across trackers; ~60-second refresh)")
            case .leeches:
                metric(swarm?.leeches)
                    .help("Tracker-reported leeches (max across trackers; ~60-second refresh)")
            case .eta:
                Text(eta).monospacedDigit().foregroundStyle(.secondary)
            case .ratio:
                Text(ratio).monospacedDigit().foregroundStyle(.secondary)
            case .addedDate:
                Text(date(torrent.addedDate)).foregroundStyle(.secondary)
            case .totalSize:
                byteCount(torrent.totalSize)
            case .downloaded:
                byteCount(torrent.downloadedEver)
            case .uploaded:
                byteCount(torrent.uploadedEver)
            case .remaining:
                byteCount(torrent.leftUntilDone)
            case .connectedPeers:
                metric(torrent.peersConnected)
            case .queuePosition:
                metric(torrent.queuePosition)
            case .priority:
                Text(LocalizedStringKey(torrentPriorityLabel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Based on file priorities")
            }
        }
        .font(.subheadline)
        .lineLimit(1)
    }

    private var torrentPriorityLabel: String {
        switch torrent.filePrioritySummary {
        case .unknown: "—"
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        case .mixed: "Mixed"
        }
    }

    private var iconName: String {
        switch torrent.status {
        case 0: "pause.fill"
        case 4: "play.fill"
        case 6: "checkmark.circle.fill"
        case 1, 2: "checkmark.shield"
        default: "clock"
        }
    }

    private var iconColor: Color {
        switch torrent.status {
        case 0: .secondary
        case 4: .blue
        case 6: .green
        default: .secondary
        }
    }

    private func metric(_ count: Int?) -> some View {
        Text(count.map(String.init) ?? "—")
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }

    private func byteCount(_ bytes: Int64?) -> some View {
        Text(bytes.map {
            ByteCountFormatter.string(fromByteCount: max($0, 0), countStyle: .binary)
        } ?? "—")
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }

    private var ratio: String {
        guard let ratio = torrent.uploadRatio, ratio >= 0, ratio.isFinite else {
            return "—"
        }
        return ratio.formatted(.number.precision(.fractionLength(2)))
    }

    private var eta: String {
        switch torrent.eta {
        case let seconds where seconds >= 0:
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            return h > 0 ? "\(h)h \(m)m" : "\(m)m"
        case -1:
            return "—"
        default:
            return "∞"
        }
    }

    private func date(_ time: Int?) -> String {
        guard let time, time > 0 else { return "—" }
        return Date(timeIntervalSince1970: TimeInterval(time))
            .formatted(date: .numeric, time: .shortened)
    }
}
