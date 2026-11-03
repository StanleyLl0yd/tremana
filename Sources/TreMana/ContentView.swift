import SwiftUI
import TreManaCore
import UniformTypeIdentifiers

private enum TorrentFilter: Hashable {
    case all
    case downloading
    case seeding
}

struct ContentView: View {
    @Environment(TreManaModel.self) private var model
    @State private var filter: TorrentFilter? = .all
    @State private var showingVerifyConfirmation = false
    @State private var showingAddTorrent = false

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
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showingAddTorrent = true
                    } label: {
                        Label("Add Torrent", systemImage: "plus")
                    }
                    .disabled(model.isBusy)

                    Button {
                        Task { await model.perform(.start) }
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .disabled(model.isBusy || model.selectedTorrentIDs.isEmpty)

                    Button {
                        Task { await model.perform(.stop) }
                    } label: {
                        Label("Stop", systemImage: "pause.fill")
                    }
                    .disabled(model.isBusy || model.selectedTorrentIDs.isEmpty)

                    Button {
                        showingVerifyConfirmation = true
                    } label: {
                        Label("Verify", systemImage: "checkmark.shield")
                    }
                    .disabled(model.isBusy || model.selectedTorrentIDs.isEmpty)

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
        .sheet(isPresented: $showingAddTorrent) {
            AddTorrentSheet()
        }
        .onChange(of: filter) { _, _ in
            model.selectedTorrentIDs.removeAll()
        }
        .confirmationDialog(
            "Verify \(model.selectedTorrentIDs.count) selected torrent(s)?",
            isPresented: $showingVerifyConfirmation,
            titleVisibility: .visible
        ) {
            Button("Verify") {
                Task { await model.perform(.verify) }
            }
        } message: {
            Text("Verification can temporarily interrupt active transfers.")
        }
    }
}

private struct ConnectionView: View {
    @Environment(TreManaModel.self) private var model

    var body: some View {
        @Bindable var form = model

        Form {
            Section("Saved Profiles") {
                Picker("Profile", selection: $form.selectedProfileID) {
                    Text("Custom connection").tag(nil as UUID?)
                    ForEach(model.savedProfiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .onChange(of: model.selectedProfileID) { _, id in
                    Task { await model.chooseProfile(id) }
                }

                TextField("Profile name", text: $form.profileName)
                Toggle("Remember password in Keychain", isOn: $form.rememberPassword)

                HStack {
                    Button("Save Profile") {
                        Task { await model.saveCurrentProfile() }
                    }
                    .disabled(model.profilesBusy || model.isBusy)

                    Button("Delete Profile") {
                        Task { await model.deleteSelectedProfile() }
                    }
                    .disabled(
                        model.selectedProfileID == nil ||
                        model.profilesBusy || model.isBusy
                    )
                }

                if model.rememberPassword && model.password.isEmpty {
                    Text("A saved Keychain password is used only when the server address and username match the saved profile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let profileError = model.profileErrorMessage {
                    Text(profileError)
                        .foregroundStyle(.red)
                }
            }

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
                .disabled(model.isBusy || model.profilesBusy)
            }
            if let message = model.errorMessage {
                Text(message)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Connection error: \(message)")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Connect to Transmission")
        .task { await model.reloadProfiles() }
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
        @Bindable var observedModel = model

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
            Table(filteredTorrents, selection: $observedModel.selectedTorrentIDs) {
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
            if let notice = model.noticeMessage {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
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


private enum TorrentSourceMode: Hashable {
    case magnet
    case file
}

private struct AddTorrentSheet: View {
    @Environment(TreManaModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var mode: TorrentSourceMode = .magnet
    @State private var magnet = ""
    @State private var startImmediately = true
    @State private var showingFileImporter = false
    @State private var selectedFileName: String?
    @State private var selectedFileData: Data?
    @State private var fileError: String?

    private var canAdd: Bool {
        guard model.isConnected, !model.isBusy else { return false }
        switch mode {
        case .magnet:
            return !magnet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .file:
            return selectedFileData != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Torrent")
                .font(.title2)

            Picker("Source", selection: $mode) {
                Text("Magnet link").tag(TorrentSourceMode.magnet)
                Text(".torrent file").tag(TorrentSourceMode.file)
            }
            .pickerStyle(.segmented)

            if mode == .magnet {
                TextField("magnet:?xt=urn:btih:…", text: $magnet)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            } else {
                Button("Choose .torrent File…") {
                    showingFileImporter = true
                }
                if let selectedFileName {
                    Text(selectedFileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Start immediately", isOn: $startImmediately)

            if let fileError {
                Text(fileError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    let source: TorrentAddSource
                    switch mode {
                    case .magnet:
                        source = .magnet(magnet)
                    case .file:
                        guard let selectedFileData else { return }
                        source = .metainfo(selectedFileData)
                    }
                    dismiss()
                    Task {
                        await model.addTorrent(
                            source, startImmediately: startImmediately
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdd)
            }
        }
        .padding(24)
        .frame(width: 480)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "torrent") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else {
                    selectedFileName = nil
                    selectedFileData = nil
                    fileError = "No .torrent file was selected."
                    return
                }
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                let limit = 16 * 1024 * 1024
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                guard url.pathExtension.lowercased() == "torrent",
                      let size, size > 0, size <= limit else {
                    selectedFileName = nil
                    selectedFileData = nil
                    fileError = "Select a .torrent file between 1 byte and 16 MiB."
                    return
                }
                let data = try Data(contentsOf: url)
                guard !data.isEmpty, data.count <= limit else {
                    selectedFileName = nil
                    selectedFileData = nil
                    fileError = "Select a .torrent file between 1 byte and 16 MiB."
                    return
                }
                selectedFileName = url.lastPathComponent
                selectedFileData = data
                fileError = nil
            } catch {
                selectedFileName = nil
                selectedFileData = nil
                fileError = error.localizedDescription
            }
        }
    }
}
