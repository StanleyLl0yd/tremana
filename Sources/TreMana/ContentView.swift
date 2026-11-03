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
    @Environment(\.scenePhase) private var scenePhase
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
        .task(id: "\(model.isConnected)-\(scenePhase == .active)") {
            // SwiftUI cancels this task when connection or scene activity changes.
            // Sleep before refresh: connect and torrent mutations already fetch immediately.
            while !Task.isCancelled && model.isConnected {
                let delay = RefreshPolicy.intervalSeconds(
                    torrents: model.torrents,
                    isForeground: scenePhase == .active,
                    hadError: model.errorMessage != nil
                )
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    break
                }
                guard !Task.isCancelled && model.isConnected else { break }
                // Model excludes concurrent RPC polls while a mutation or refresh is in flight.
                await model.refresh()
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
            Section {
                ConnectionHero()
            }
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
                .disabled(model.isBusy || model.profilesBusy)

                TextField("Profile name (optional)", text: $form.profileName)
                Toggle("Remember this connection", isOn: $form.rememberPassword)

                if model.rememberPassword {
                    Text("After a successful connection, TreMana saves this profile. Passwords are kept in macOS Keychain, never in app settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if model.canReuseSavedPassword && model.rememberPassword
                    && model.password.isEmpty {
                    Label("Password saved securely. Leave the field empty to reuse it.", systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if model.selectedProfileID != nil {
                    Button("Forget Selected Connection") {
                        Task { await model.deleteSelectedProfile() }
                    }
                    .disabled(model.profilesBusy || model.isBusy)
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
        .navigationTitle("Connection")
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

    private var activeCount: Int {
        model.torrents.filter { [1, 2, 4].contains($0.status) }.count
    }

    private var seedingCount: Int {
        model.torrents.filter { $0.status == 6 }.count
    }

    private var footerMessage: String? {
        model.profileErrorMessage ?? model.errorMessage ?? model.noticeMessage
    }

    private var isError: Bool {
        model.profileErrorMessage != nil || model.errorMessage != nil
    }

    var body: some View {
        @Bindable var observedModel = model

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Torrents")
                            .font(.title2.weight(.semibold))
                        if let server = model.server {
                            Text("Transmission \(server.version) · RPC \(server.rpcVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    GlassEffectContainer(spacing: 12) {
                        ZenStatusPill(
                            title: "\(activeCount) active",
                            symbol: "arrow.down.circle"
                        )
                        ZenStatusPill(
                            title: "\(seedingCount) seeding",
                            symbol: "arrow.up.circle"
                        )
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("Sequential piece downloading is not supported by this server")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 16)

            Divider()

            Table(filteredTorrents, selection: $observedModel.selectedTorrentIDs) {
                TableColumn("Name", value: \.name)
                TableColumn("Progress") { torrent in
                    TorrentProgressCell(progress: torrent.percentDone)
                }
                TableColumn("Status") { torrent in
                    TorrentStatusCell(status: torrent.status)
                }
                TableColumn("Download") { torrent in
                    TransferRateCell(bytesPerSecond: torrent.rateDownload)
                }
                TableColumn("Upload") { torrent in
                    TransferRateCell(bytesPerSecond: torrent.rateUpload)
                }
            }
            .accessibilityLabel("Transmission torrents")

            Divider()

            HStack(spacing: 10) {
                if let footerMessage {
                    Image(systemName: isError ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundStyle(isError ? Color.red : Color.secondary)
                    Text(footerMessage)
                        .foregroundStyle(isError ? Color.red : Color.secondary)
                        .lineLimit(2)
                        .help(footerMessage)
                } else {
                    Image(systemName: model.isBusy ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Text(model.isBusy ? "Syncing…" : "Connected")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let last = model.lastRefreshAt {
                    Text("Updated \(last, format: .dateTime.hour().minute().second())")
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .accessibilityLabel("Last refreshed \(last.formatted())")
                }
            }
            .font(.caption)
            .padding(.horizontal, 22)
            .frame(height: 48)
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
