import SwiftUI
import AppKit
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
    @State private var showingAddTorrent = false
    @AppStorage(ToolbarPresentation.storageKey) private var toolbarPresentation = ToolbarPresentation.iconsAndLabels.rawValue

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
                if model.isConnected {
                    List(selection: $filter) {
                        Label("All Torrents", systemImage: "tray.full")
                            .tag(TorrentFilter.all)
                        Label("Downloading", systemImage: "arrow.down.circle")
                            .tag(TorrentFilter.downloading)
                        Label("Seeding", systemImage: "arrow.up.circle")
                            .tag(TorrentFilter.seeding)
                    }
                    .listStyle(.sidebar)
                } else {
                    Spacer()
                }
                if let version = Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString"
                ) as? String {
                    HStack {
                        Text(version)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("TreMana version \(version)")
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
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
                        presentation: $toolbarPresentation
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
        .task(id: refreshLoopIdentity) {
            guard model.isConnected, autoRefreshEnabled else { return }
            await model.refreshSwarm()
            while !Task.isCancelled && model.isConnected {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    break
                }
                guard !Task.isCancelled, model.isConnected else { break }
                await model.refreshSwarm()
            }
        }
        .task(id: refreshLoopIdentity) {
            guard model.isConnected else { return }
            await model.advanceStrictFileQueues()
            while !Task.isCancelled && model.isConnected {
                do {
                    try await Task.sleep(for: .seconds(12))
                } catch {
                    break
                }
                guard !Task.isCancelled, model.isConnected else { break }
                await model.advanceStrictFileQueues()
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
    }
}

enum ToolbarPresentation: String, CaseIterable, Identifiable {
    case icons = "icons"
    case iconsAndLabels = "icons-and-labels"
    case labels = "labels"

    static let storageKey = "com.sl.tremana.toolbarPresentation"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .icons: "Icons only"
        case .iconsAndLabels: "Icons and labels"
        case .labels: "Labels only"
        }
    }
}

private struct TorrentCommandBar: View {
    @Environment(TreManaModel.self) private var model

    let showSidebar: Bool
    let revealSidebar: () -> Void
    let add: () -> Void
    @Binding var presentation: String

    private var selectedPresentation: ToolbarPresentation {
        ToolbarPresentation(rawValue: presentation) ?? .iconsAndLabels
    }

    var body: some View {
        HStack(spacing: 10) {
            if showSidebar {
                ToolbarActionButton(
                    title: "Show Sidebar", symbol: "sidebar.left",
                    presentation: selectedPresentation, action: revealSidebar
                )
            }

            ToolbarActionButton(
                title: "Disconnect", symbol: "network.slash",
                presentation: selectedPresentation
            ) {
                model.disconnect()
            }
            Divider().frame(height: 18)

            ToolbarActionButton(
                title: "Add Torrent", symbol: "plus",
                presentation: selectedPresentation, action: add
            )
            .disabled(model.isBusy)
            .accessibilityIdentifier("toolbar.add-torrent")

            ToolbarActionButton(
                title: "Start", symbol: "play.fill",
                presentation: selectedPresentation
            ) {
                Task { await model.perform(.start) }
            }
            .disabled(model.isBusy || model.selectedTorrentIDs.isEmpty)

            ToolbarActionButton(
                title: "Pause", symbol: "pause.fill",
                presentation: selectedPresentation
            ) {
                Task { await model.perform(.stop) }
            }
            .disabled(model.isBusy || model.selectedTorrentIDs.isEmpty)

            Spacer(minLength: 0)

            Menu {
                Picker("Toolbar appearance", selection: $presentation) {
                    ForEach(ToolbarPresentation.allCases) { option in
                        Text(LocalizedStringKey(option.title))
                            .tag(option.rawValue)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if selectedPresentation != .labels {
                        Image(systemName: "slider.horizontal.3")
                    }
                    if selectedPresentation != .icons {
                        Text("Toolbar")
                            .lineLimit(1)
                    }
                }
                .frame(minHeight: 28)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Toolbar appearance")
            .accessibilityLabel("Toolbar appearance")
        }
        .font(.subheadline)
        .padding(.horizontal, 15)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }
}

private struct ToolbarActionButton: View {
    let title: String
    let symbol: String
    let presentation: ToolbarPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if presentation != .labels {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .medium))
                }
                if presentation != .icons {
                    Text(LocalizedStringKey(title))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(minHeight: 27)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(LocalizedStringKey(title))
        .accessibilityLabel(LocalizedStringKey(title))
    }
}

private struct ConnectionView: View {
    @Environment(TreManaModel.self) private var model

    var body: some View {
        @Bindable var form = model

        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    ConnectionHero()
                    HStack {
                        Button {
                            Task { await model.connect() }
                        } label: {
                            HStack(spacing: 8) {
                                if model.isBusy {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "network")
                                }
                                Text("Connect")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .disabled(
                            model.isConnected || model.isBusy || model.profilesBusy
                                || model.rpcURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                        .help("Connect")
                        .accessibilityIdentifier("connection.primary-connect")
                        Spacer()
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
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
    @State private var inspectorExpanded = false
    @State private var inspectorTab: InspectorTab = .overview
    @State private var pendingVerifyIDs: [Int] = []
    @State private var pendingRemoveIDs: [Int] = []
    @State private var showingVerifyDialog = false
    @State private var showingRemoveDialog = false
    @State private var remoteActionRequest: RemoteTorrentActionRequest?
    @State private var queueRequestID: Int?
    @State private var queueRequestEnabled = false
    @State private var showingQueueConfirmation = false
    @State private var showingPiecesLimitation = false
    @SceneStorage("com.sl.tremana.table-columns.v1")
    private var columnCustomization: TableColumnCustomization<TransmissionTorrent>

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
            if inspectorExpanded {
                TorrentInspectorView(isExpanded: $inspectorExpanded, selectedTab: $inspectorTab)
                    .frame(maxHeight: .infinity)
            } else {
                VSplitView {
                    Table(
                        filteredTorrents,
                        selection: $observedModel.selectedTorrentIDs,
                        columnCustomization: $columnCustomization
                    ) {
                        TableColumnForEach(TorrentColumn.allCases) { column in
                            TableColumn(LocalizedStringKey(column.title)) { torrent in
                                TorrentColumnCell(
                                    column: column,
                                    torrent: torrent,
                                    swarm: model.swarmCounts[torrent.id]
                                )
                            }
                            .customizationID(column.rawValue)
                            .defaultVisibility(column.visibleByDefault ? .visible : .hidden)
                        }
                    }
                    .contextMenu(forSelectionType: Int.self) { selection in
                        Button {
                            Task { await model.perform(.start, ids: Array(selection)) }
                        } label: {
                            Label("Start", systemImage: "play.fill")
                        }
                        .disabled(selection.isEmpty || model.isBusy)

                        Button {
                            Task { await model.perform(.startNow, ids: Array(selection)) }
                        } label: {
                            Label("Start Now", systemImage: "play.circle.fill")
                        }
                        .disabled(selection.isEmpty || model.isBusy)

                        Button {
                            Task { await model.perform(.stop, ids: Array(selection)) }
                        } label: {
                            Label("Pause", systemImage: "pause.fill")
                        }
                        .disabled(selection.isEmpty || model.isBusy)

                        Divider()

                        Button {
                            pendingVerifyIDs = Array(selection).sorted()
                            showingVerifyDialog = true
                        } label: {
                            Label("Verify Downloaded Data…", systemImage: "checkmark.shield")
                        }
                        .disabled(selection.isEmpty || model.isBusy)

                        Button {
                            Task { await model.perform(.reannounce, ids: Array(selection)) }
                        } label: {
                            Label("Reannounce to Trackers", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(selection.isEmpty || model.isBusy)

                        if selection.count == 1, let id = selection.first {
                            Divider()
                            Button {
                                Task {
                                    guard let link = await model.magnetLink(for: id) else { return }
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(link, forType: .string)
                                }
                            } label: {
                                Label("Copy Magnet Link", systemImage: "link")
                            }

                            Divider()

                            Button {
                                queueRequestID = id
                                queueRequestEnabled = !model.strictQueueTorrentIDs.contains(id)
                                showingQueueConfirmation = true
                            } label: {
                                Label(
                                    LocalizedStringKey(model.strictQueueTorrentIDs.contains(id)
                                        ? "Stop downloading files in order…"
                                        : "Download files in order…"),
                                    systemImage: "list.number"
                                )
                            }
                            .disabled(model.isBusy)

                            Button {
                                showingPiecesLimitation = true
                            } label: {
                                Label("Download pieces in order…", systemImage: "rectangle.split.3x1")
                            }

                            Divider()

                            Button {
                                remoteActionRequest = RemoteTorrentActionRequest(
                                    torrentID: id, kind: .move
                                )
                            } label: {
                                Label("Move Server Data…", systemImage: "folder")
                            }
                            .disabled(model.isBusy)

                            Button {
                                remoteActionRequest = RemoteTorrentActionRequest(
                                    torrentID: id, kind: .rename
                                )
                            } label: {
                                Label("Rename Server File or Folder…", systemImage: "pencil")
                            }
                            .disabled(model.isBusy)
                        }

                        Divider()

                        Button(role: .destructive) {
                            pendingRemoveIDs = Array(selection).sorted()
                            showingRemoveDialog = true
                        } label: {
                            Label("Remove Torrent…", systemImage: "trash")
                        }
                        .disabled(selection.isEmpty || model.isBusy)
                    }
                    .accessibilityLabel("Transmission torrents")
                    .alternatingRowBackgrounds(.disabled)
                    .frame(minHeight: 85)
                    TorrentInspectorView(isExpanded: $inspectorExpanded, selectedTab: $inspectorTab)
                        .frame(minHeight: 120, idealHeight: 315)
                }
            }

            Divider()

            HStack(spacing: 9) {
                if let footerMessage {
                    Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle")
                        .foregroundStyle(isError ? Color.red : Color.secondary)
                    Group {
                        if footerMessage == "Connection remembered securely" {
                            Text("Connection remembered securely")
                        } else if footerMessage == "File selection updated" {
                            Text("File selection updated")
                        } else if footerMessage == "Server move confirmed" {
                            Text("Server move confirmed")
                        } else if footerMessage == "Server path rename confirmed" {
                            Text("Server path rename confirmed")
                        } else {
                            Text(footerMessage)
                        }
                    }
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(isError ? Color.red : Color.secondary)
                        .help(LocalizedStringKey(footerMessage))
                } else {
                    Label(LocalizedStringKey(model.isBusy ? "Applying…" : model.isRefreshing ? "Syncing…" : "Connected"),
                          systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                if let server = model.server {
                    Text("Transmission \(server.version) · RPC \(server.rpcVersion)")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Divider().frame(height: 15)
                    Label("\(activeCount)", systemImage: "arrow.down.circle")
                        .help("Active transfers")
                    Label("\(seedingCount)", systemImage: "arrow.up.circle")
                        .help("Seeding torrents")
                    Divider().frame(height: 15)
                }
                if let last = model.lastRefreshAt {
                    Text(last, format: .dateTime.hour().minute().second())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .help("Last refreshed: \(last.formatted())")
                }
            }
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 34)
        }
        .confirmationDialog(
            "Strict file queue",
            isPresented: $showingQueueConfirmation,
            titleVisibility: .visible
        ) {
            Button(LocalizedStringKey(queueRequestEnabled
                ? "Enable ordered file downloading" : "Disable ordered file downloading")) {
                if let id = queueRequestID {
                    Task { await model.setStrictFileQueue(torrentID: id, enabled: queueRequestEnabled) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("When enabled, only the current file downloads. The next file starts after completion while TreMana is connected. If the Mac sleeps or the app closes, the next file waits.")
        }
        .alert("Sequential pieces unavailable", isPresented: $showingPiecesLimitation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Transmission 3.00 / RPC 16 cannot schedule pieces in order. No setting was changed.")
        }
        .sheet(item: $remoteActionRequest) { request in
            RemoteTorrentActionSheet(request: request)
        }
        .confirmationDialog(
            "Verify \(pendingVerifyIDs.count) torrent(s)?",
            isPresented: $showingVerifyDialog,
            titleVisibility: .visible
        ) {
            Button("Verify Downloaded Data") {
                let ids = pendingVerifyIDs
                Task { await model.perform(.verify, ids: ids) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Transmission rereads local pieces and checks their BitTorrent hashes. It does not scan for viruses and may temporarily interrupt transfers.")
        }
        .confirmationDialog(
            "Remove \(pendingRemoveIDs.count) torrent(s) from Transmission?",
            isPresented: $showingRemoveDialog,
            titleVisibility: .visible
        ) {
            Button("Remove Torrent, Keep Files") {
                let ids = pendingRemoveIDs
                Task { await model.removeTorrents(ids: ids, deleteLocalData: false) }
            }
            Button("Remove Torrent and Delete Server Files", role: .destructive) {
                let ids = pendingRemoveIDs
                Task { await model.removeTorrents(ids: ids, deleteLocalData: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove affects Transmission on the Keenetic. Choosing Delete Server Files permanently removes downloaded data from the server. This cannot be undone by TreMana.")
        }
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
