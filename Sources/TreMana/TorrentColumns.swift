import SwiftUI
import TreManaCore

enum TorrentColumn: String, CaseIterable, Identifiable {
    case name, progress, status, download, upload
    case seeds, leeches, eta, ratio, addedDate, totalSize
    case downloaded, uploaded, remaining, connectedPeers, queuePosition

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
        }
    }

    var visibleByDefault: Bool {
        switch self {
        case .name, .progress, .status, .download, .upload,
             .seeds, .leeches, .eta, .ratio: true
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
                Text(torrent.name).lineLimit(1).help(torrent.name)
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
            }
        }
        .font(.subheadline)
        .lineLimit(1)
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
