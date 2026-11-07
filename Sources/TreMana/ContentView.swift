import SwiftUI
import AppKit
import TreManaCore
import UniformTypeIdentifiers

private enum TorrentFilter: Hashable {
    case all
    case active
    case completed
    case paused
}

struct ContentView: View {
    let model: TreManaModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appearsActive) private var appearsActive
    @AppStorage(RefreshPreferenceKeys.enabled) private var autoRefreshEnabled = true
    @AppStorage(RefreshPreferenceKeys.mode) private var refreshMode = RefreshMode.adaptive.rawValue
    @AppStorage(RefreshPreferenceKeys.fixedInterval) private var fixedInterval = 10
    @State private var filter: TorrentFilter? = .all
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var showingAddTorrent = false
    @State private var searchText = ""
    @State private var connectionContentHeight: CGFloat = 300
    @State private var connectionRequiresScroll = false
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
        Group {
            if model.isConnected {
                NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                HStack {
                    Text("Downloads")
                        .font(.caption.weight(.medium))
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
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 8)

                List(selection: $filter) {
                    sidebarItem("All Torrents", icon: "tray.full", filter: .all,
                                count: model.torrents.count)
                    sidebarItem("Active", icon: "arrow.down.circle", filter: .active,
                                count: model.torrents.filter { [1, 2, 3, 4, 5, 6].contains($0.status) }.count)
                    sidebarItem("Completed", icon: "checkmark.circle", filter: .completed,
                                count: model.torrents.filter { $0.percentDone >= 1 }.count)
                    sidebarItem("Paused", icon: "pause.circle", filter: .paused,
                                count: model.torrents.filter { $0.status == 0 }.count)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)

            }
            .background(.ultraThinMaterial)
            .navigationTitle("TreMana")
            .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                TorrentCommandBar(
                    model: model,
                    showSidebar: columnVisibility == .detailOnly,
                    revealSidebar: { columnVisibility = .all },
                    add: { showingAddTorrent = true },
                    presentation: $toolbarPresentation,
                    searchText: $searchText
                )
                Divider()
                TorrentTableView(model: model, filter: filter ?? .all, searchText: searchText)
            }
        }
            } else {
                NavigationStack {
                    ConnectionView(
                        model: model,
                        measuredHeight: $connectionContentHeight,
                        requiresScroll: $connectionRequiresScroll
                    )
                }
            }
        }
        .background { TreManaWindowTint() }
        .overlay(alignment: .topLeading) {
            TreManaWindowSizing(
                isConnected: model.isConnected,
                disconnectedContentHeight: connectionContentHeight,
                onScrollRequirementChange: { connectionRequiresScroll = $0 }
            )
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
            AddTorrentSheet(model: model)
        }
        .onChange(of: filter) { _, _ in
            model.selectedTorrentIDs.removeAll()
        }
    }

    private func sidebarItem(
        _ title: String, icon: String, filter: TorrentFilter, count: Int
    ) -> some View {
        HStack(spacing: 8) {
            Label(LocalizedStringKey(title), systemImage: icon)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(count, format: .number)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .tag(filter)
        .padding(.vertical, 3)
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
    let model: TreManaModel

    let showSidebar: Bool
    let revealSidebar: () -> Void
    let add: () -> Void
    @Binding var presentation: String
    @Binding var searchText: String

    private var selectedPresentation: ToolbarPresentation {
        ToolbarPresentation(rawValue: presentation) ?? .iconsAndLabels
    }

    private var connectionName: String {
        if let profile = model.savedProfiles.first(where: {
            $0.id == model.selectedProfileID
        }) {
            return profile.name
        }
        return URL(string: model.rpcURL)?.host ?? "Transmission"
    }

    var body: some View {
        HStack(spacing: 8) {
            if showSidebar {
                Button(action: revealSidebar) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 24, height: 27)
                }
                .buttonStyle(.borderless)
                .help("Show Sidebar")
                .accessibilityLabel("Show Sidebar")
                .accessibilityIdentifier("toolbar.reveal-sidebar")
            }

            ToolbarActionButton(
                title: "Disconnect", symbol: "network.slash",
                presentation: selectedPresentation, action: model.disconnect
            )
            .accessibilityIdentifier("toolbar.disconnect")

            Text(connectionName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(connectionName)

            Rectangle()
                .fill(.secondary.opacity(0.4))
                .frame(width: 1, height: 18)

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

            Spacer(minLength: 6)

            TextField("Search torrents", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 112, idealWidth: 165, maxWidth: 190)
                .accessibilityLabel("Search torrents")
        }
        .font(.subheadline)
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17))
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
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
    let model: TreManaModel
    @Binding var measuredHeight: CGFloat
    @Binding var requiresScroll: Bool
    @State private var editingConnection = false

    /// A stored connection needs only its selector and Connect button. Avoid
    /// showing an editable RPC form on every launch, especially on short screens.
    private var showConnectionEditor: Bool {
        editingConnection || model.savedProfiles.isEmpty || model.selectedProfileID == nil
    }

    var body: some View {
        Group {
            if requiresScroll {
                ScrollView { connectionForm }
                    .scrollIndicators(.automatic)
            } else {
                connectionForm
            }
        }
        .background { TreManaWindowTint() }
        .navigationTitle("Connection")
        .task { await model.reloadProfiles() }
    }

    /// Measure the entire form before deciding whether scrolling is necessary.
    /// An always-present ScrollView measures the viewport instead on some macOS layouts.
    private var connectionForm: some View {
        @Bindable var form = model
        return VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 12) {
                    ConnectionHero()
                    Spacer(minLength: 8)
                    Button {
                        Task { await model.connect() }
                    } label: {
                        if model.isBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Connect", systemImage: "network")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        model.isConnected || model.isBusy || model.profilesBusy
                            || model.rpcURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .fixedSize()
                    .accessibilityIdentifier("connection.primary-connect")
                }
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))

                if !model.savedProfiles.isEmpty {
                    CompactFormSection("Saved Profiles") {
                        CompactFormRow("Profile") {
                            Picker("Profile", selection: $form.selectedProfileID) {
                                Text("Custom connection").tag(nil as UUID?)
                                ForEach(model.savedProfiles) { profile in
                                    Text(profile.name).tag(Optional(profile.id))
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 210)
                            .onChange(of: model.selectedProfileID) { _, id in
                                editingConnection = id == nil
                                Task { await model.chooseProfile(id) }
                            }
                            .disabled(model.isBusy || model.profilesBusy)
                        }
                        if !showConnectionEditor {
                            Divider().padding(.leading, 13)
                            CompactFormRow("Server URL") {
                                Text(model.rpcURL)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(.secondary)
                                    .help(model.rpcURL)
                            }
                        }
                    }
                }

                if model.selectedProfileID != nil {
                    Button {
                        editingConnection.toggle()
                    } label: {
                        Label(
                            LocalizedStringKey(editingConnection
                                ? "Hide connection settings" : "Edit connection"),
                            systemImage: editingConnection
                                ? "chevron.up" : "slider.horizontal.3"
                        )
                        .font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 4)
                    .disabled(model.isBusy || model.profilesBusy)
                    .accessibilityIdentifier("connection.toggle-editor")
                }

                if showConnectionEditor {
                    CompactFormSection("Connection settings") {
                        CompactFormRow("Profile name (optional)") {
                            TextField("Profile name (optional)", text: $form.profileName)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 230)
                        }
                        Divider().padding(.leading, 13)
                        CompactFormRow("Remember this connection") {
                            Toggle("Remember this connection", isOn: $form.rememberPassword)
                                .labelsHidden()
                                .help("After a successful connection, TreMana saves this profile. Passwords are kept in macOS Keychain, never in app settings.")
                        }
                        if model.hasMatchingSavedProfile && model.rememberPassword
                            && model.password.isEmpty {
                            Divider().padding(.leading, 13)
                            Label(
                                LocalizedStringKey(model.canReuseSavedPassword
                                    ? "Password saved securely. Leave the field empty to reuse it."
                                    : "Leave the password blank to reuse a saved password, if available."),
                                systemImage: model.canReuseSavedPassword
                                    ? "checkmark.shield" : "key.horizontal"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                        }
                        if model.selectedProfileID != nil {
                            Divider().padding(.leading, 13)
                            HStack {
                                Button("Forget Selected Connection") {
                                    Task { await model.deleteSelectedProfile() }
                                }
                                .buttonStyle(.borderless)
                                .disabled(model.profilesBusy || model.isBusy)
                                Spacer()
                            }
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                        }
                    }

                    CompactFormSection("Transmission RPC") {
                        CompactFormRow("Server URL") {
                            TextField("Server URL", text: $form.rpcURL)
                                .textContentType(.URL)
                                .autocorrectionDisabled()
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 300)
                        }
                        Divider().padding(.leading, 13)
                        CompactFormRow("Username") {
                            TextField("Username", text: $form.username)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 230)
                        }
                        Divider().padding(.leading, 13)
                        CompactFormRow("Password") {
                            SecureField("Password", text: $form.password)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 230)
                        }
                        Divider().padding(.leading, 13)
                        CompactFormRow("Allow unencrypted HTTP (trusted local network only)") {
                            Toggle(
                                "Allow unencrypted HTTP (trusted local network only)",
                                isOn: $form.allowsInsecureHTTP
                            )
                            .labelsHidden()
                        }
                    }
                }

                if let profileError = model.profileErrorMessage {
                    Text(profileError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                }
                if let message = model.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Connection error: \(message)")
                        .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: 604)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                if AdaptiveWindowHeight.shouldUpdate(
                    previous: Double(measuredHeight), measured: Double(height)
                ) {
                    measuredHeight = height
                }
            }
    }
}

private struct TorrentTableView: View {
    let model: TreManaModel
    let filter: TorrentFilter
    let searchText: String
    @AppStorage("com.sl.tremana.inspector-tab.v1") private var inspectorTabName = InspectorTab.files.rawValue
    @AppStorage(InspectorSplitSizing.storageKey) private var inspectorFraction = InspectorSplitSizing.defaultFraction
    @State private var splitDragStart: Double?
    @State private var splitDragPreview: Double?
    @State private var pendingVerifyIDs: [Int] = []
    @State private var pendingRemoveIDs: [Int] = []
    @State private var showingVerifyDialog = false
    @State private var showingRemoveDialog = false
    @State private var remoteActionRequest: RemoteTorrentActionRequest?
    @State private var queueRequestID: Int?
    @State private var queueRequestEnabled = false
    @State private var showingQueueConfirmation = false
    @State private var showingPiecesLimitation = false
    @SceneStorage("com.sl.tremana.table-columns.v2")
    private var columnCustomization: TableColumnCustomization<TransmissionTorrent>

    private var selectedInspectorTab: Binding<InspectorTab> {
        Binding(
            get: { InspectorTab(rawValue: inspectorTabName) ?? .files },
            set: { inspectorTabName = $0.rawValue }
        )
    }

    private func adjustInspector(_ drag: DragGesture.Value, totalHeight: Double) {
        let start = splitDragStart ?? inspectorFraction
        if splitDragStart == nil { splitDragStart = start }
        let available = max(1, totalHeight - InspectorSplitSizing.dividerHeight)
        let proposed = start * available - Double(drag.translation.height)
        splitDragPreview = InspectorSplitSizing.fraction(
            forInspectorHeight: proposed, totalHeight: totalHeight
        )
    }

    private func finishInspectorDrag() {
        if let splitDragPreview { inspectorFraction = splitDragPreview }
        splitDragStart = nil
        splitDragPreview = nil
    }

    private var filteredTorrents: [TransmissionTorrent] {
        let filtered: [TransmissionTorrent]
        switch filter {
        case .all:
            filtered = model.torrents
        case .active:
            filtered = model.torrents.filter { [1, 2, 3, 4, 5, 6].contains($0.status) }
        case .completed:
            filtered = model.torrents.filter { $0.percentDone >= 1 }
        case .paused:
            filtered = model.torrents.filter { $0.status == 0 }
        }
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return filtered }
        return filtered.filter { $0.name.localizedStandardContains(term) }
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
            GeometryReader { geometry in
                let availableHeight = Double(geometry.size.height)
                let sizing = InspectorSplitSizing(
                    totalHeight: availableHeight,
                    preferredFraction: splitDragPreview ?? inspectorFraction
                )
                VStack(spacing: 0) {
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
                .frame(height: sizing.torrentsHeight)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Capsule()
                    .fill(.secondary.opacity(0.5))
                    .frame(width: 38, height: 3)
                    .frame(maxWidth: .infinity)
                    .frame(height: InspectorSplitSizing.dividerHeight)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { adjustInspector($0, totalHeight: availableHeight) }
                            .onEnded { _ in finishInspectorDrag() }
                    )
                    .help("Resize torrent details")
                    .accessibilityLabel("Resize torrent details")
                    .accessibilityAdjustableAction { direction in
                        let delta = direction == .increment ? 0.05 : -0.05
                        inspectorFraction = InspectorSplitSizing.fraction(
                            forInspectorHeight: (inspectorFraction + delta)
                                * max(1, availableHeight - InspectorSplitSizing.dividerHeight),
                            totalHeight: availableHeight
                        )
                    }

                TorrentInspectorView(model: model, selectedTab: selectedInspectorTab)
                    .frame(height: sizing.inspectorHeight)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 9)

            Divider().opacity(0.35)

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
                if let version = Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString"
                ) as? String {
                    Text("TreMana \(version)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .help("TreMana version \(version)")
                        .accessibilityLabel("TreMana version \(version)")
                    Divider().frame(height: 15)
                }
                if let server = model.server {
                    Text("Transmission \(server.version)")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Divider().frame(height: 15)
                    Label(
                        ByteCountFormatter.string(
                            fromByteCount: model.torrents.reduce(Int64(0)) {
                                $0 &+ max(Int64(0), $1.rateDownload)
                            },
                            countStyle: .binary
                        ) + "/s",
                        systemImage: "arrow.down"
                    )
                    .foregroundStyle(.secondary)
                    Label(
                        ByteCountFormatter.string(
                            fromByteCount: model.torrents.reduce(Int64(0)) {
                                $0 &+ max(Int64(0), $1.rateUpload)
                            },
                            countStyle: .binary
                        ) + "/s",
                        systemImage: "arrow.up"
                    )
                    .foregroundStyle(.secondary)
                    Divider().frame(height: 15)
                    Label("\(activeCount)", systemImage: "square.stack")
                        .help("Active transfers")
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
            RemoteTorrentActionSheet(model: model, request: request)
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
    let model: TreManaModel
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
