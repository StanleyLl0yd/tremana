import SwiftUI
import TreManaCore

struct RemoteTorrentActionRequest: Identifiable {
    enum Kind { case move, rename }
    let id = UUID()
    let torrentID: Int
    let kind: Kind
}

struct RemoteTorrentActionSheet: View {
    @Environment(TreManaModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let request: RemoteTorrentActionRequest

    @State private var detail: TransmissionTorrentDetail?
    @State private var loaded = false
    @State private var destination = ""
    @State private var path = ""
    @State private var newName = ""
    @State private var submitting = false
    @State private var confirming = false
    @State private var error: String?

    private var candidates: [String] {
        RemoteTorrentPath.renameCandidates(files: detail?.files ?? [])
    }

    private var canSubmit: Bool {
        guard let detail, !submitting, !model.isBusy else { return false }
        switch request.kind {
        case .move:
            return (try? RemoteTorrentPath.destination(destination)) != nil
                && destination != detail.downloadDir
        case .rename:
            guard candidates.contains(path),
                  (try? RemoteTorrentPath.name(newName)) != nil else {
                return false
            }
            let parts = path.split(separator: "/")
            let updated = (parts.dropLast().map(String.init) + [newName])
                .joined(separator: "/")
            return updated != path && !candidates.contains(updated)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.kind == .move
                 ? "Move Data on Transmission Server"
                 : "Rename File or Folder on Transmission Server")
                .font(.title3.weight(.semibold))

            if let detail {
                LabeledContent("Torrent", value: detail.name)

                switch request.kind {
                case .move:
                    LabeledContent("Current server folder", value: detail.downloadDir ?? "Unknown")
                    TextField("Destination folder on server", text: $destination)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Destination folder on server")
                    Text("Enter an absolute folder path on the Keenetic server, not a Mac Finder path. Ensure that the server has permission and enough free space. Data will be moved remotely.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .rename:
                    if candidates.isEmpty {
                        ContentUnavailableView(
                            "No safe path available to rename",
                            systemImage: "exclamationmark.triangle"
                        )
                    } else {
                        Picker("Existing server path", selection: $path) {
                            ForEach(candidates, id: \.self) { candidate in
                                Text(candidate).tag(candidate)
                            }
                        }
                        .accessibilityLabel("Existing server path")
                        TextField("New file or folder name", text: $newName)
                            .textFieldStyle(.roundedBorder)
                        Text("Only the selected file or folder on the Transmission server is renamed. This does not rename an arbitrary torrent display title or a local Finder item.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if loaded {
                ContentUnavailableView(
                    "Unable to load current server paths",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error ?? "Please reopen the action.")
                )
            } else {
                HStack {
                    ProgressView()
                    Text("Checking current torrent paths…")
                }
            }

            if let error, detail != nil {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(request.kind == .move ? "Move Server Data…" : "Rename Server Path…") {
                    confirming = true
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 560)
        .task {
            let loadedDetail = await model.remoteActionDetail(for: request.torrentID)
            loaded = true
            guard let loadedDetail else {
                error = model.errorMessage ?? "Please reopen the action."
                return
            }
            detail = loadedDetail
            destination = loadedDetail.downloadDir ?? ""
            if let first = candidates.first {
                path = first
                newName = first.split(separator: "/").last.map(String.init) ?? ""
            }
        }
        .onChange(of: path) { _, updated in
            newName = updated.split(separator: "/").last.map(String.init) ?? ""
        }
        .confirmationDialog(
            LocalizedStringKey(request.kind == .move
                               ? "Confirm server-side move?"
                               : "Confirm server-side rename?"),
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(request.kind == .move ? "Move Server Data" : "Rename Server Path",
                   role: .destructive) {
                Task { await submit() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(request.kind == .move
                 ? "Transmission will move files on the Keenetic server. This may take time and cannot be undone by TreMana."
                 : "Transmission will rename this file or folder on the server. Other clients may need to refresh their file lists.")
        }
    }

    @MainActor
    private func submit() async {
        guard let detail, !submitting else { return }
        submitting = true
        defer { submitting = false }
        error = nil

        let success: Bool
        switch request.kind {
        case .move:
            success = await model.moveTorrent(to: destination, expected: detail)
        case .rename:
            success = await model.renameTorrentPath(path, to: newName, expected: detail)
        }
        if success {
            dismiss()
        } else {
            error = model.errorMessage ?? "Transmission did not confirm the operation."
        }
    }
}
