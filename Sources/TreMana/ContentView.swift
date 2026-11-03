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
    @Environment(\.appearsActive) private var appearsActive
    @AppStorage(RefreshPreferenceKeys.enabled) private var autoRefreshEnabled = true
    @AppStorage(RefreshPreferenceKeys.mode) private var refreshMode = RefreshMode.adaptive.rawValue
    @AppStorage(RefreshPreferenceKeys.fixedInterval) private var fixedInterval = 10
    @State private var filter: TorrentFilter? = .all
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingVerifyConfirmation = false
    @State private var showingAddTorrent = false

    private var refreshConfiguration: RefreshConfiguration {
        RefreshConfiguration(
            enabled: autoRefreshEnabled,
            mode: RefreshMode(rawValue: refreshMode) ?? .adaptive,
            fixedIntervalSeconds: fixedInterval
        )
    }

    private var isWindowForeground: Bool {
        scenePhase == .active && appearsActive
    }

    private var refreshLoopIdentity: String {
        "\(model.isConnected)-\(isWindowForeground)-\(autoRefreshEnabled)-\(refreshMode)-\(fixedInterval)"
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                HStack {
                    Text("LIBRARY")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button {
                        columnVisibility = .detailOnly
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .buttonStyle(.borderless)
                    .help("Hide Sidebar")
                    .accessibilityLabel("Hide Sidebar")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                List(selection: $filter) {
                    Label("All Torrents", systemImage: "tray.full")
                        .tag(TorrentFilter.all)
                    Label("Downloading", systemImage: "arrow.down.circle")
                        .tag(TorrentFilter.downloading)
                    Label("Seeding", systemImage: "arrow.up.circle")
                        .tag(TorrentFilter.seeding)
                }
                .listStyle(.sidebar)
            }
            .navigationTitle("TreMana")
            .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                if model.isConnected {
                    TorrentCommandBar(
                        showSidebar: columnVisibility == .detailOnly,
                        revealSidebar: { columnVisibility = .all },
                        add: { showingAddTorrent = true },
                        verify: { showingVerifyConfirmation = true }
                    )
                    Divider()
                    TorrentTableView(filter: filter ?? .all)
                } else {
                    if columnVisibility == .detailOnly {
                        HStack {
                            Button {
                                columnVisibility = .all
                            } label: {
                                Label("Show Sidebar", systemImage: "sidebar.left")
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 9)
                    }
                    ConnectionView()
                }
            }
        }
        .task(id: refreshLoopIdentity) {
            // SwiftUI cancels the task when connection, phase or settings change.
            // First sleep avoids redundant fetch after Connect or torrent mutations.
            while !Task.isCancelled && model.isConnected {
                guard let delay = refreshConfiguration.intervalSeconds(
                    torrents: model.torrents,
                    isForeground: isWindowForeground,
                    hadError: model.errorMessage != nil
                ) else { break }
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    break
                }
                guard !Task.isCancelled && model.isConnected else { break }
                await model.refresh()
            }
        }
        .onChange(of: isWindowForeground) { wasForeground, isForeground in
            if !wasForeground && isForeground,
               model.isConnected && autoRefreshEnabled {
                // Return to an already connected window with fresh data.
                Task { await model.refresh() }
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

private struct TorrentCommandBar: View {
    @Environment(TreManaModel.self) private var model

    let showSidebar: Bool
    let revealSidebar: () -> Void
    let add: () -> Void
    let verify: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if showSidebar {
                Button(action: revealSidebar) {
                    Label("Show Sidebar", systemImage: "sidebar.left")
                }
                .help("Show Sidebar")
            }
            CommandButton(title: "Add Torrent", symbol: "plus", action: add)
                .disabled(model.isBusy)
            CommandButton(title: "Start", symbol: "play.fill") {
                Task { await model.perform(.start) }
            }
            .disabled(model.isBusy || model.selectedTorrentIDs.isEmpty)
            CommandButton(title: "Pause", symbol: "pause.fill") {
                Task { await model.perform(.stop) }
            }
            .disabled(model.isBusy || model.selectedTorrentIDs.isEmpty)
            CommandButton(title: "Verify", symbol: "checkmark.shield", action: verify)
                .disabled(model.isBusy || model.selectedTorrentIDs.isEmpty)
            CommandButton(title: "Refresh", symbol: "arrow.clockwise") {
                Task { await model.refresh() }
            }
            .disabled(model.isBusy || model.isRefreshing)
            CommandButton(title: "Disconnect", symbol: "network.slash") {
                model.disconnect()
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

private struct CommandButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .frame(height: 23)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: 80, height: 50)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.bordered)
        .help(title)
        .accessibilityLabel(title)
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

            VSplitView {
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
                .frame(minHeight: 175)

                TorrentInspectorView()
                    .frame(minHeight: 185, idealHeight: 260)
            }

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
                    Image(systemName: model.isBusy || model.isRefreshing ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Text(model.isBusy ? "Applying changes…" : model.isRefreshing ? "Syncing…" : "Connected")
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
