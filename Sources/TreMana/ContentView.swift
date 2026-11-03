import SwiftUI
import TreManaCore

private enum TorrentFilter: Hashable {
    case all
    case downloading
    case seeding
}

struct ContentView: View {
    @Environment(TreManaModel.self) private var model
    @State private var filter: TorrentFilter? = .all

    var body: some View {
        NavigationSplitView {
            List(selection: $filter) {
                Label("All Torrents", systemImage: "tray.full")
                    .tag(TorrentFilter.all)
                Label("Downloading", systemImage: "arrow.down.circle")
                    .tag(TorrentFilter.downloading)
                Label("Seeding", systemImage: "arrow.up.circle")
                    .tag(TorrentFilter.seeding)
            }
            .navigationTitle("TreMana")
            .listStyle(.sidebar)
        } detail: {
            if model.isConnected {
                TorrentTableView(filter: filter ?? .all)
            } else {
                ConnectionView()
            }
        }
        .toolbar {
            if model.isConnected {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isBusy)
                }
                ToolbarItem {
                    Button("Disconnect") { model.disconnect() }
                }
            }
        }
    }
}

private struct ConnectionView: View {
    @Environment(TreManaModel.self) private var model

    var body: some View {
        @Bindable var form = model

        Form {
            Section("Transmission RPC") {
                TextField("Server URL", text: $form.rpcURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                TextField("Username", text: $form.username)
                SecureField("Password", text: $form.password)
                Toggle("Allow unencrypted HTTP (trusted local network only)",
                       isOn: $form.allowsInsecureHTTP)
            }
            Section {
                Button("Connect") {
                    Task { await model.connect() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
            }
            if let message = model.errorMessage {
                Text(message)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Connection error: \(message)")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Connect to Transmission")
    }
}

private struct TorrentTableView: View {
    @Environment(TreManaModel.self) private var model
    let filter: TorrentFilter

    private var filteredTorrents: [TransmissionTorrent] {
        switch filter {
        case .all: model.torrents
        case .downloading: model.torrents.filter { $0.status == 4 }
        case .seeding: model.torrents.filter { $0.status == 6 }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let server = model.server {
                HStack {
                    Text("Transmission \(server.version) · RPC \(server.rpcVersion)")
                    Spacer()
                    Text("Sequential pieces: unavailable on this server")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
            }
            Table(filteredTorrents) {
                TableColumn("Name", value: \.name)
                TableColumn("Progress") { torrent in
                    Text(torrent.percentDone, format: .percent.precision(.fractionLength(1)))
                }
                TableColumn("Status") { torrent in
                    Text(torrent.statusDescription)
                }
                TableColumn("Download") { torrent in
                    Text(
                        ByteCountFormatter.string(
                            fromByteCount: torrent.rateDownload,
                            countStyle: .binary
                        ) + "/s"
                    )
                }
                TableColumn("Upload") { torrent in
                    Text(
                        ByteCountFormatter.string(
                            fromByteCount: torrent.rateUpload,
                            countStyle: .binary
                        ) + "/s"
                    )
                }
            }
            if let message = model.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
        .navigationTitle("Torrents")
    }
}
