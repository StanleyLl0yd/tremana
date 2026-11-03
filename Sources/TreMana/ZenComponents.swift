import SwiftUI
import TreManaCore

struct ConnectionHero: View {
    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 64, height: 64)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 5) {
                Text("Connect to Transmission")
                    .font(.title2.weight(.semibold))
                Text("Your downloads, quietly under control.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

struct TorrentProgressCell: View {
    let progress: Double

    private var boundedProgress: Double { min(1, max(0, progress)) }

    var body: some View {
        HStack(spacing: 9) {
            ProgressView(value: boundedProgress)
                .progressViewStyle(.linear)
                .accessibilityLabel("Torrent progress")
                .accessibilityValue(boundedProgress.formatted(.percent))
            Text(boundedProgress, format: .percent.precision(.fractionLength(1)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 48, alignment: .trailing)
        }
    }
}

struct TorrentStatusCell: View {
    @Environment(\.backgroundProminence) private var backgroundProminence
    let status: Int

    private var iconName: String {
        switch status {
        case 1, 2: "checkmark.shield"
        case 3, 4: "arrow.down.circle"
        case 5, 6: "arrow.up.circle"
        case 0: "pause.circle"
        default: "questionmark.circle"
        }
    }

    private var label: String {
        switch status {
        case 0: "Stopped"
        case 1, 2: "Verifying"
        case 3: "Download queued"
        case 4: "Downloading"
        case 5: "Seed queued"
        case 6: "Seeding"
        default: "Unknown"
        }
    }

    var body: some View {
        Label(LocalizedStringKey(label), systemImage: iconName)
            .font(.subheadline)
            .foregroundStyle(
                backgroundProminence == .increased
                    ? AnyShapeStyle(Color.white)
                    : AnyShapeStyle(Color.primary)
            )
            .lineLimit(1)
    }
}

struct TransferRateCell: View {
    let bytesPerSecond: Int64

    var body: some View {
        Text(
            ByteCountFormatter.string(
                fromByteCount: max(0, bytesPerSecond),
                countStyle: .binary
            ) + "/s"
        )
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}
