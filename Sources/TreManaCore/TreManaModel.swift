import Foundation
import Observation

public protocol TransmissionRPCProviding: Sendable {
    func sessionInfo() async throws -> TransmissionSession
    func torrents() async throws -> [TransmissionTorrent]
    func torrentSwarm() async throws -> [Int: TorrentSwarmCounts]
    func torrentDetails(id: Int) async throws -> TransmissionTorrentDetail?
    func setFileWanted(torrentID: Int, fileIndex: Int, wanted: Bool) async throws
    func setFilePriority(torrentID: Int, fileIndex: Int, priority: Int) async throws
    func setFilesPriority(torrentID: Int, fileIndices: [Int], priority: Int) async throws
    func setQueueFileSelection(
        torrentID: Int, wanted: [Int], unwanted: [Int]
    ) async throws
    func moveTorrent(torrentID: Int, destination: String) async throws
    func renameTorrentPath(torrentID: Int, path: String, name: String) async throws
    func perform(_ action: TorrentAction, ids: [Int]) async throws
    func removeTorrents(ids: [Int], deleteLocalData: Bool) async throws
    func magnetLink(id: Int) async throws -> String?
    func addTorrent(_ source: TorrentAddSource, startImmediately: Bool) async throws -> TorrentAddOutcome
}

extension TransmissionRPCProviding {
    public func setFileWanted(torrentID: Int, fileIndex: Int, wanted: Bool) async throws {
        throw TransmissionRPCError.invalidFileSelection
    }

    public func setFilePriority(torrentID: Int, fileIndex: Int, priority: Int) async throws {
        throw TransmissionRPCError.invalidFilePriority
    }

    public func setFilesPriority(
        torrentID: Int, fileIndices: [Int], priority: Int
    ) async throws {
        throw TransmissionRPCError.invalidFilePriority
    }

    public func setQueueFileSelection(
        torrentID: Int, wanted: [Int], unwanted: [Int]
    ) async throws {
        throw TransmissionRPCError.invalidFileSelection
    }

    public func moveTorrent(torrentID: Int, destination: String) async throws {
        throw TransmissionRPCError.invalidRemotePath
    }

    public func renameTorrentPath(torrentID: Int, path: String, name: String) async throws {
        throw TransmissionRPCError.invalidRenameName
    }

    public func torrentSwarm() async throws -> [Int: TorrentSwarmCounts] { [:] }

    public func removeTorrents(ids: [Int], deleteLocalData: Bool) async throws {
        throw TransmissionRPCError.invalidTorrentSelection
    }

    public func magnetLink(id: Int) async throws -> String? {
        throw TransmissionRPCError.invalidTorrentSelection
    }
}

extension TransmissionRPCClient: TransmissionRPCProviding {}


/// Explicit, bounded batch operation for one selected torrent.
/// Never translates file selection into a priority change or vice versa.
public enum FileBatchAction: Sendable, Equatable {
    case download(Bool)
    case priority(Int)
}

@MainActor
@Observable
public final class TreManaModel {
    public var rpcURL = "http://192.168.1.1:8090/transmission/rpc"
    public var username = ""
    public var password = ""
    public var allowsInsecureHTTP = false
    public var selectedTorrentIDs: Set<Int> = []
    public var selectedProfileID: UUID?
    public var profileName = ""
    public var rememberPassword = false
    public private(set) var savedPasswordAvailable = false

    public private(set) var isBusy = false
    public private(set) var isRefreshing = false
    public private(set) var errorMessage: String?
    public private(set) var noticeMessage: String?
    public private(set) var profileErrorMessage: String?
    public private(set) var profilesBusy = false
    public private(set) var savedProfiles: [ConnectionProfile] = []
    public private(set) var server: TransmissionSession?
    public private(set) var torrents: [TransmissionTorrent] = []
    public private(set) var swarmCounts: [Int: TorrentSwarmCounts] = [:]
    public private(set) var isRefreshingSwarm = false
    public private(set) var lastRefreshAt: Date?
    public private(set) var selectedTorrentDetail: TransmissionTorrentDetail?
    public private(set) var detailErrorMessage: String?
    public private(set) var isLoadingDetail = false
    public private(set) var strictQueueTorrentIDs: Set<Int> = []
    public private(set) var strictQueuePendingIDs: Set<Int> = []

    @ObservationIgnored
    private let makeClient: @MainActor (TransmissionConnection) -> any TransmissionRPCProviding

    @ObservationIgnored
    private var client: (any TransmissionRPCProviding)?

    @ObservationIgnored
    private var connectionGeneration: UInt64 = 0

    @ObservationIgnored
    private var mutationGeneration: UInt64 = 0

    @ObservationIgnored
    private var profileSelectionGeneration: UInt64 = 0

    @ObservationIgnored
    private var detailGeneration: UInt64 = 0

    @ObservationIgnored
    private var editingFileSelectionForID: Int?

    @ObservationIgnored
    private let profileStore: any ConnectionProfileStoring

    @ObservationIgnored
    private let strictQueueController: StrictFileQueueController

    public var isConnected: Bool { server != nil && client != nil }

    public var canReuseSavedPassword: Bool {
        guard savedPasswordAvailable,
              let saved = savedProfiles.first(where: { $0.id == selectedProfileID }) else {
            return false
        }
        return saved.rpcURL == rpcURL
            && saved.username == username
            && saved.allowsInsecureHTTP == allowsInsecureHTTP
    }

    public init(
        makeClient: @escaping @MainActor (TransmissionConnection) -> any TransmissionRPCProviding = {
            TransmissionRPCClient(connection: $0)
        },
        profileStore: any ConnectionProfileStoring = UserDefaultsProfileStore(),
        strictQueueDefaults: UserDefaults = .standard
    ) {
        self.makeClient = makeClient
        self.profileStore = profileStore
        self.strictQueueController = StrictFileQueueController(defaults: strictQueueDefaults)
    }

    public func reloadProfiles() async {
        guard !profilesBusy else { return }
        profilesBusy = true
        defer { profilesBusy = false }
        do {
            let loaded = try await profileStore.list()
            savedProfiles = loaded
            profileErrorMessage = nil
            if selectedProfileID == nil && password.isEmpty && username.isEmpty {
                let preferred = await profileStore.preferredProfileID()
                let id = loaded.first(where: { $0.id == preferred })?.id
                    ?? loaded.first?.id
                if let id {
                    await chooseProfile(id)
                }
            }
        } catch {
            profileErrorMessage = error.localizedDescription
        }
    }

    public func chooseProfile(_ id: UUID?) async {
        profileSelectionGeneration &+= 1
        let generation = profileSelectionGeneration
        selectedProfileID = id
        password = ""
        rememberPassword = false
        savedPasswordAvailable = false
        profileErrorMessage = nil

        guard let id else {
            profileName = ""
            return
        }
        guard let profile = savedProfiles.first(where: { $0.id == id }) else {
            selectedProfileID = nil
            profileErrorMessage = ProfileStorageError.profileNotFound.localizedDescription
            return
        }

        profileName = profile.name
        rpcURL = profile.rpcURL
        username = profile.username
        allowsInsecureHTTP = profile.allowsInsecureHTTP
        do {
            let stored = try await profileStore.password(for: id)
            guard profileSelectionGeneration == generation else { return }
            // Never populate the text field with secrets retrieved from Keychain.
            rememberPassword = true
            savedPasswordAvailable = stored != nil
            await profileStore.setPreferredProfileID(id)
        } catch {
            guard profileSelectionGeneration == generation else { return }
            profileErrorMessage = error.localizedDescription
        }
    }

    public func deleteSelectedProfile() async {
        guard !profilesBusy, let id = selectedProfileID else { return }
        profilesBusy = true
        defer { profilesBusy = false }

        do {
            try await profileStore.remove(id: id)
            savedProfiles = try await profileStore.list()
            profileSelectionGeneration &+= 1
            selectedProfileID = nil
            profileName = ""
            rememberPassword = false
            savedPasswordAvailable = false
            password = ""
            profileErrorMessage = nil
        } catch {
            profileErrorMessage = error.localizedDescription
        }
    }

    public func connect() async {
        guard !isBusy, !profilesBusy, !isConnected else { return }
        connectionGeneration &+= 1
        let generation = connectionGeneration
        isBusy = true
        defer {
            if connectionGeneration == generation {
                isBusy = false
            }
        }
        errorMessage = nil
        profileErrorMessage = nil

        // Capture the user's explicit choice before asynchronous network work.
        let requestedURL = rpcURL
        let requestedUsername = username
        let enteredPassword = password
        let shouldRemember = rememberPassword
        let chosenProfileID = selectedProfileID
        let requestedName = profileName
        let insecureHTTP = allowsInsecureHTTP

        do {
            guard let url = URL(string: requestedURL) else {
                throw TransmissionRPCError.invalidURL
            }
            let existing = savedProfiles.first(where: { $0.id == chosenProfileID })
            let sameEndpoint = existing?.rpcURL == requestedURL
                && existing?.username == requestedUsername
                && existing?.allowsInsecureHTTP == insecureHTTP

            var effectivePassword = enteredPassword
            if effectivePassword.isEmpty,
               sameEndpoint, shouldRemember, let chosenProfileID,
               !requestedUsername.isEmpty {
                effectivePassword = try await profileStore.password(for: chosenProfileID) ?? ""
                guard connectionGeneration == generation else { return }
            }

            let credentials: RPCBasicCredentials? = requestedUsername.isEmpty
                ? nil
                : RPCBasicCredentials(
                    username: requestedUsername, password: effectivePassword
                )
            let connection = try TransmissionConnection(
                url: url,
                credentials: credentials,
                allowInsecureHTTP: insecureHTTP
            )
            let newClient = makeClient(connection)
            let info = try await newClient.sessionInfo()
            guard connectionGeneration == generation else { return }
            let loaded = try await newClient.torrents()
            guard connectionGeneration == generation else { return }

            server = info
            client = newClient
            torrents = loaded
            swarmCounts = [:]
            lastRefreshAt = .now
            detailGeneration &+= 1
            selectedTorrentDetail = nil
            detailErrorMessage = nil
            selectedTorrentIDs = []
            noticeMessage = nil
            password = ""
            strictQueueTorrentIDs = strictQueueController.enabledTorrentIDs(endpoint: requestedURL)
            strictQueuePendingIDs = strictQueueController.pendingTorrentIDs(endpoint: requestedURL)

            guard shouldRemember else { return }
            // Never reuse an existing profile's credential on a changed endpoint.
            let identicalProfile = sameEndpoint ? existing : savedProfiles.first {
                $0.rpcURL == requestedURL
                    && $0.username == requestedUsername
                    && $0.allowsInsecureHTTP == insecureHTTP
            }
            let id = identicalProfile?.id ?? UUID()
            let name = identicalProfile == nil && existing != nil
                ? (url.host ?? "Transmission")
                : (requestedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? (identicalProfile?.name ?? url.host ?? "Transmission")
                    : requestedName)
            let profile = ConnectionProfile(
                id: id, name: name, rpcURL: requestedURL,
                username: requestedUsername, allowsInsecureHTTP: insecureHTTP
            )
            let update: ProfilePasswordUpdate
            if requestedUsername.isEmpty || effectivePassword.isEmpty {
                update = .remove
            } else if sameEndpoint && enteredPassword.isEmpty {
                update = .keep
            } else {
                update = .replace(effectivePassword)
            }

            do {
                try await profileStore.save(profile, password: update)
                let refreshed = try await profileStore.list()
                await profileStore.setPreferredProfileID(id)
                guard connectionGeneration == generation else { return }

                savedProfiles = refreshed
                selectedProfileID = id
                profileName = profile.name
                savedPasswordAvailable = !requestedUsername.isEmpty
                    && !effectivePassword.isEmpty
                profileErrorMessage = nil
                noticeMessage = "Connection remembered securely"
            } catch {
                guard connectionGeneration == generation else { return }
                profileErrorMessage = "Connected, but saving failed: \(error.localizedDescription)"
            }
        } catch {
            guard connectionGeneration == generation else { return }
            errorMessage = error.localizedDescription
        }
    }

    public func refreshSwarm() async {
        guard let client, !isRefreshingSwarm, !isBusy else { return }
        let ticket = connectionGeneration
        isRefreshingSwarm = true
        defer {
            if connectionGeneration == ticket { isRefreshingSwarm = false }
        }
        do {
            let counts = try await client.torrentSwarm()
            guard connectionGeneration == ticket else { return }
            swarmCounts = counts
        } catch {
            // Supplementary tracker data must never interrupt torrent controls.
        }
    }

    public func loadSelectedTorrentDetails() async {
        // Suppress old detail snapshots for the edited torrent, but allow
        // an immediate detail load if the user switches to a different torrent.
        if let editingFileSelectionForID,
           selectedTorrentIDs == Set([editingFileSelectionForID]) {
            return
        }
        detailGeneration &+= 1
        let ticket = detailGeneration
        let connectionTicket = connectionGeneration

        guard let client, selectedTorrentIDs.count == 1,
              let id = selectedTorrentIDs.first, id > 0,
              torrents.contains(where: { $0.id == id }) else {
            selectedTorrentDetail = nil
            detailErrorMessage = nil
            isLoadingDetail = false
            return
        }

        if selectedTorrentDetail?.id != id { selectedTorrentDetail = nil }
        detailErrorMessage = nil
        isLoadingDetail = true
        defer {
            if detailGeneration == ticket {
                isLoadingDetail = false
            }
        }

        do {
            let item = try await client.torrentDetails(id: id)
            guard connectionGeneration == connectionTicket,
                  detailGeneration == ticket,
                  selectedTorrentIDs == Set([id]) else { return }
            selectedTorrentDetail = item
            if item == nil {
                detailErrorMessage = "The selected torrent is no longer available."
            }
        } catch {
            guard connectionGeneration == connectionTicket,
                  detailGeneration == ticket,
                  selectedTorrentIDs == Set([id]) else { return }
            detailErrorMessage = error.localizedDescription
        }
    }

    public func setFileWanted(
        torrentID: Int,
        fileIndex: Int,
        wanted: Bool,
        expectedWanted: Bool
    ) async {
        guard let client, !isBusy else { return }
        guard !strictQueueTorrentIDs.contains(torrentID) else {
            errorMessage = TransmissionRPCError.fileSelectionChanged.localizedDescription
            return
        }
        guard torrentID > 0,
              selectedTorrentIDs == Set([torrentID]),
              torrents.contains(where: { $0.id == torrentID }),
              let displayed = selectedTorrentDetail,
              displayed.id == torrentID,
              let displayedFiles = displayed.files,
              let displayedStats = displayed.fileStats,
              displayedFiles.count == displayedStats.count,
              displayedFiles.indices.contains(fileIndex),
              displayedStats[fileIndex].wanted == expectedWanted,
              expectedWanted != wanted else {
            errorMessage = TransmissionRPCError.invalidFileSelection.localizedDescription
            return
        }

        mutationGeneration &+= 1
        detailGeneration &+= 1
        isLoadingDetail = false
        detailErrorMessage = nil
        let ticket = connectionGeneration
        isBusy = true
        editingFileSelectionForID = torrentID
        defer {
            if connectionGeneration == ticket {
                editingFileSelectionForID = nil
                isBusy = false
            }
        }

        do {
            // Recheck the live daemon selection before changing it; the
            // inspector may have been stale or another client may have edited it.
            let current = try await client.torrentDetails(id: torrentID)
            guard connectionGeneration == ticket,
                  selectedTorrentIDs == Set([torrentID]) else { return }
            guard let current,
                  let displayedHash = displayed.hashString,
                  !displayedHash.isEmpty,
                  current.hashString == displayedHash,
                  let files = current.files,
                  let stats = current.fileStats,
                  files.count == stats.count,
                  files.count == displayedFiles.count,
                  files.indices.contains(fileIndex),
                  files[fileIndex].name == displayedFiles[fileIndex].name,
                  files[fileIndex].length == displayedFiles[fileIndex].length else {
                throw TransmissionRPCError.invalidFileSelection
            }
            guard stats[fileIndex].wanted == expectedWanted else {
                selectedTorrentDetail = current
                throw TransmissionRPCError.fileSelectionChanged
            }
            if !wanted && stats.filter(\.wanted).count <= 1 {
                throw TransmissionRPCError.lastWantedFile
            }

            try await client.setFileWanted(
                torrentID: torrentID, fileIndex: fileIndex, wanted: wanted
            )
            guard connectionGeneration == ticket,
                  selectedTorrentIDs == Set([torrentID]) else { return }

            // RPC success alone is not enough to claim the UI has changed.
            selectedTorrentDetail = nil
            let refreshed = try await client.torrentDetails(id: torrentID)
            guard connectionGeneration == ticket,
                  selectedTorrentIDs == Set([torrentID]) else { return }
            guard let refreshed,
                  let verified = refreshed.fileStats,
                  verified.indices.contains(fileIndex) else {
                throw TransmissionRPCError.invalidFileSelection
            }
            selectedTorrentDetail = refreshed
            guard verified[fileIndex].wanted == wanted else {
                throw TransmissionRPCError.fileSelectionChanged
            }
            errorMessage = nil
            noticeMessage = "File selection updated"
        } catch {
            guard connectionGeneration == ticket else { return }
            errorMessage = error.localizedDescription
            noticeMessage = nil
            if selectedTorrentDetail == nil {
                detailErrorMessage = error.localizedDescription
            }
        }
    }

    public func setFilePriority(
        torrentID: Int,
        fileIndex: Int,
        priority: Int,
        expectedPriority: Int
    ) async {
        guard let client, !isBusy else { return }
        guard (-1...1).contains(priority),
              (-1...1).contains(expectedPriority),
              priority != expectedPriority,
              torrentID > 0,
              selectedTorrentIDs == Set([torrentID]),
              torrents.contains(where: { $0.id == torrentID }),
              let displayed = selectedTorrentDetail,
              displayed.id == torrentID,
              let displayedFiles = displayed.files,
              let displayedStats = displayed.fileStats,
              displayedFiles.count == displayedStats.count,
              displayedFiles.indices.contains(fileIndex),
              displayedStats[fileIndex].priority == expectedPriority else {
            errorMessage = TransmissionRPCError.invalidFilePriority.localizedDescription
            return
        }

        mutationGeneration &+= 1
        detailGeneration &+= 1
        isLoadingDetail = false
        detailErrorMessage = nil
        let ticket = connectionGeneration
        isBusy = true
        editingFileSelectionForID = torrentID
        defer {
            if connectionGeneration == ticket {
                editingFileSelectionForID = nil
                isBusy = false
            }
        }

        do {
            let current = try await client.torrentDetails(id: torrentID)
            guard connectionGeneration == ticket,
                  selectedTorrentIDs == Set([torrentID]) else { return }
            guard let current,
                  let displayedHash = displayed.hashString,
                  !displayedHash.isEmpty,
                  current.hashString == displayedHash,
                  let files = current.files,
                  let stats = current.fileStats,
                  files.count == stats.count,
                  files.count == displayedFiles.count,
                  files.indices.contains(fileIndex),
                  files[fileIndex].name == displayedFiles[fileIndex].name,
                  files[fileIndex].length == displayedFiles[fileIndex].length else {
                throw TransmissionRPCError.invalidFileSelection
            }
            guard stats[fileIndex].priority == expectedPriority else {
                selectedTorrentDetail = current
                throw TransmissionRPCError.invalidFilePriority
            }

            try await client.setFilePriority(
                torrentID: torrentID, fileIndex: fileIndex, priority: priority
            )
            guard connectionGeneration == ticket,
                  selectedTorrentIDs == Set([torrentID]) else { return }

            selectedTorrentDetail = nil
            let refreshed = try await client.torrentDetails(id: torrentID)
            guard connectionGeneration == ticket,
                  selectedTorrentIDs == Set([torrentID]) else { return }
            guard let refreshed,
                  let verified = refreshed.fileStats,
                  verified.indices.contains(fileIndex) else {
                throw TransmissionRPCError.invalidFileSelection
            }
            selectedTorrentDetail = refreshed
            guard verified[fileIndex].priority == priority else {
                throw TransmissionRPCError.invalidFilePriority
            }
            errorMessage = nil
            noticeMessage = "File priority updated"
        } catch {
            guard connectionGeneration == ticket else { return }
            errorMessage = error.localizedDescription
            noticeMessage = nil
            if selectedTorrentDetail == nil {
                detailErrorMessage = error.localizedDescription
            }
        }
    }

    public func applyFileBatch(
        torrentID: Int, indices requestedIndices: [Int], action: FileBatchAction
    ) async {
        guard let client, !isBusy, torrentID > 0,
              selectedTorrentIDs == Set([torrentID]),
              torrents.contains(where: { $0.id == torrentID }),
              let displayed = selectedTorrentDetail,
              displayed.id == torrentID,
              let displayedHash = displayed.hashString, !displayHash.isEmpty,
              let displayedFiles = displayed.files,
              let displayedStats = displayed.fileStats,
              !displayedFiles.isEmpty,
              displayedFiles.count == displayedStats.count,
              !requestedIndices.isEmpty,
              Set(requestedIndices).count == requestedIndices.count,
              requestedIndices.allSatisfy({ displayedFiles.indices.contains($0) })
        else {
            errorMessage = TransmissionRPCError.invalidFileSelection.localizedDescription
            return
        }
        let indices = requestedIndices.sorted()
        if case .download = action, strictQueueTorrentIDs.contains(torrentID) {
            errorMessage = TransmissionRPCError.fileSelectionChanged.localizedDescription
            return
        }
        if case let .priority(value) = action, !(-1...1).contains(value) {
            errorMessage = TransmissionRPCError.invalidFilePriority.localizedDescription
            return
        }

        mutationGeneration &+= 1
        detailGeneration &+= 1
        isLoadingDetail = false
        detailErrorMessage = nil
        let ticket = connectionGeneration
        isBusy = true
        editingFileSelectionForID = torrentID
        defer {
            if connectionGeneration == ticket {
                editingFileSelectionForID = nil
                isBusy = false
            }
        }

        do {
            guard let current = try await client.torrentDetails(id: torrentID),
                  connectionGeneration == ticket,
                  selectedTorrentIDs == Set([torrentID]) else { return }
            guard current.hashString == displayedHash,
                  let files = current.files, let stats = current.fileStats,
                  files.count == displayedFiles.count,
                  stats.count == displayedStats.count,
                  zip(files, displayedFiles).allSatisfy({
                      $0.name == $1.name && $0.length == $1.length
                  }),
                  zip(stats, displayedStats).allSatisfy({
                      $0.wanted == $1.wanted && $0.priority == $1.priority
                  }) else {
                selectedTorrentDetail = current
                throw TransmissionRPCError.fileSelectionChanged
            }

            switch action {
            case .download(let download):
                var desired = stats.map(\.wanted)
                for index in indices { desired[index] = download }
                guard desired.contains(true) else {
                    throw TransmissionRPCError.lastWantedFile
                }
                guard desired != stats.map(\.wanted) else { return }
                let wanted = desired.indices.filter { desired[$0] }
                let unwanted = desired.indices.filter { !desired[$0] }
                try await client.setQueueFileSelection(
                    torrentID: torrentID, wanted: wanted, unwanted: unwanted
                )
            case .priority(let value):
                guard indices.contains(where: { stats[$0].priority != value }) else {
                    return
                }
                try await client.setFilesPriority(
                    torrentID: torrentID, fileIndices: indices, priority: value
                )
            }
            guard connectionGeneration == ticket,
                  selectedTorrentIDs == Set([torrentID]) else { return }
            selectedTorrentDetail = nil

            guard let verified = try await client.torrentDetails(id: torrentID),
                  connectionGeneration == ticket,
                  selectedTorrentIDs == Set([torrentID]),
                  verified.hashString == displayedHash,
                  let postFiles = verified.files,
                  let postStats = verified.fileStats,
                  postFiles.count == displayedFiles.count,
                  postStats.count == displayedStats.count,
                  zip(postFiles, displayedFiles).allSatisfy({
                      $0.name == $1.name && $0.length == $1.length
                  }) else {
                throw TransmissionRPCError.fileSelectionChanged
            }
            selectedTorrentDetail = verified
            switch action {
            case .download(let download):
                guard indices.allSatisfy({ postStats[$0].wanted == download }) else {
                    throw TransmissionRPCError.fileSelectionChanged
                }
                noticeMessage = "File selection updated"
            case .priority(let value):
                guard indices.allSatisfy({ postStats[$0].priority == value }) else {
                    throw TransmissionRPCError.invalidFilePriority
                }
                noticeMessage = "File priority updated"
            }
            errorMessage = nil
            // Keep the upper torrent priority summary in sync with the inspector.
            if let refreshed = try? await client.torrents(),
               connectionGeneration == ticket {
                torrents = refreshed
            }
        } catch {
            guard connectionGeneration == ticket else { return }
            errorMessage = error.localizedDescription
            noticeMessage = nil
            if selectedTorrentDetail == nil {
                detailErrorMessage = error.localizedDescription
            }
        }
    }

    public func setStrictFileQueue(torrentID: Int, enabled: Bool) async {
        guard let client, !isBusy, torrentID > 0,
              torrents.contains(where: { $0.id == torrentID }) else { return }
        let ticket = connectionGeneration
        mutationGeneration &+= 1
        isBusy = true
        defer { if connectionGeneration == ticket { isBusy = false } }
        do {
            try await strictQueueController.setEnabled(
                enabled, torrentID: torrentID, endpoint: rpcURL, client: client
            )
            guard connectionGeneration == ticket else { return }
            strictQueueTorrentIDs = strictQueueController.enabledTorrentIDs(endpoint: rpcURL)
            strictQueuePendingIDs = strictQueueController.pendingTorrentIDs(endpoint: rpcURL)
            errorMessage = nil
            noticeMessage = enabled ? "Strict file queue enabled" : "Strict file queue disabled"
            if selectedTorrentIDs == Set([torrentID]) {
                await loadSelectedTorrentDetails()
            }
        } catch {
            guard connectionGeneration == ticket else { return }
            strictQueueTorrentIDs = strictQueueController.enabledTorrentIDs(endpoint: rpcURL)
            strictQueuePendingIDs = strictQueueController.pendingTorrentIDs(endpoint: rpcURL)
            errorMessage = error.localizedDescription
        }
    }

    public func advanceStrictFileQueues() async {
        guard let client, !isBusy, !strictQueueTorrentIDs.isEmpty else { return }
        let ticket = connectionGeneration
        mutationGeneration &+= 1
        isBusy = true
        defer { if connectionGeneration == ticket { isBusy = false } }
        do {
            try await strictQueueController.advance(endpoint: rpcURL, client: client)
            guard connectionGeneration == ticket else { return }
            strictQueueTorrentIDs = strictQueueController.enabledTorrentIDs(endpoint: rpcURL)
            strictQueuePendingIDs = strictQueueController.pendingTorrentIDs(endpoint: rpcURL)
            if selectedTorrentIDs.count == 1 {
                await loadSelectedTorrentDetails()
            }
            errorMessage = nil
        } catch {
            guard connectionGeneration == ticket else { return }
            strictQueueTorrentIDs = strictQueueController.enabledTorrentIDs(endpoint: rpcURL)
            strictQueuePendingIDs = strictQueueController.pendingTorrentIDs(endpoint: rpcURL)
            errorMessage = "Strict file queue paused: " + error.localizedDescription
        }
    }

    public func refresh() async {
        // A passive poll may not block an explicit user action.
        guard let client, !isBusy, !isRefreshing else { return }
        let generation = connectionGeneration
        let mutation = mutationGeneration
        isRefreshing = true
        defer {
            if connectionGeneration == generation {
                isRefreshing = false
            }
        }

        do {
            let loaded = try await client.torrents()
            // An action started while this GET was in flight: ignore its stale snapshot.
            guard connectionGeneration == generation,
                  mutationGeneration == mutation else { return }
            torrents = loaded
            lastRefreshAt = .now
            selectedTorrentIDs.formIntersection(Set(loaded.map(\.id)))
            errorMessage = nil
        } catch {
            guard connectionGeneration == generation,
                  mutationGeneration == mutation else { return }
            errorMessage = error.localizedDescription
        }
    }

    public func perform(_ action: TorrentAction) async {
        // Toolbar selection historically filters rows removed by a refresh.
        // Context menu actions supply exact IDs and are validated strictly.
        let existing = Set(torrents.map(\.id))
        await perform(action, ids: selectedTorrentIDs.intersection(existing).sorted())
    }

    public func perform(_ action: TorrentAction, ids requested: [Int]) async {
        guard let client, !isBusy else { return }
        let available = Set(torrents.map(\.id))
        guard !requested.isEmpty, requested.allSatisfy({
            $0 > 0 && available.contains($0)
        }) else {
            errorMessage = TransmissionRPCError.invalidTorrentSelection.localizedDescription
            return
        }
        let ids = Array(Set(requested)).sorted()

        mutationGeneration &+= 1
        let generation = connectionGeneration
        isBusy = true
        defer {
            if connectionGeneration == generation {
                isBusy = false
            }
        }

        do {
            try await client.perform(action, ids: ids)
            guard connectionGeneration == generation else { return }

            let loaded = try await client.torrents()
            guard connectionGeneration == generation else { return }

            torrents = loaded
            selectedTorrentIDs.formIntersection(Set(loaded.map(\.id)))
            errorMessage = nil
            // Mutation results are visible in the inspector immediately.
            await loadSelectedTorrentDetails()
        } catch {
            guard connectionGeneration == generation else { return }
            errorMessage = error.localizedDescription
        }
    }

    public func removeTorrents(ids requested: [Int], deleteLocalData: Bool) async {
        guard let client, !isBusy else { return }
        let available = Set(torrents.map(\.id))
        guard !requested.isEmpty, requested.allSatisfy({
            $0 > 0 && available.contains($0)
        }) else {
            errorMessage = TransmissionRPCError.invalidTorrentSelection.localizedDescription
            return
        }
        let ids = Array(Set(requested)).sorted()
        mutationGeneration &+= 1
        let ticket = connectionGeneration
        isBusy = true
        defer {
            if connectionGeneration == ticket { isBusy = false }
        }

        do {
            try await client.removeTorrents(ids: ids, deleteLocalData: deleteLocalData)
            guard connectionGeneration == ticket else { return }
            let refreshed = try await client.torrents()
            guard connectionGeneration == ticket else { return }
            torrents = refreshed
            selectedTorrentIDs.formIntersection(Set(refreshed.map(\.id)))
            let removedIDs = Set(ids).subtracting(Set(refreshed.map(\.id)))
            if !removedIDs.isEmpty {
                try? strictQueueController.forgetRemovedTorrents(
                    endpoint: rpcURL, ids: removedIDs
                )
                strictQueueTorrentIDs = strictQueueController.enabledTorrentIDs(endpoint: rpcURL)
            strictQueuePendingIDs = strictQueueController.pendingTorrentIDs(endpoint: rpcURL)
            }
            noticeMessage = deleteLocalData
                ? "Removed torrent(s) and requested deletion of server data"
                : "Removed torrent(s) from Transmission; files kept"
            errorMessage = nil
            await loadSelectedTorrentDetails()
        } catch {
            guard connectionGeneration == ticket else { return }
            errorMessage = error.localizedDescription
        }
    }


    /// A fresh, explicit per-torrent snapshot for the remote-path confirmation UI.
    public func remoteActionDetail(for torrentID: Int) async -> TransmissionTorrentDetail? {
        guard let client, !isBusy, torrentID > 0,
              torrents.contains(where: { $0.id == torrentID }) else {
            errorMessage = TransmissionRPCError.invalidTorrentSelection.localizedDescription
            return nil
        }
        let ticket = connectionGeneration
        do {
            let detail = try await client.torrentDetails(id: torrentID)
            guard connectionGeneration == ticket else { return nil }
            guard let detail, detail.id == torrentID,
                  let hash = detail.hashString, !hash.isEmpty else {
                throw TransmissionRPCError.remoteStateChanged
            }
            errorMessage = nil
            return detail
        } catch {
            guard connectionGeneration == ticket else { return nil }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public func moveTorrent(
        to destination: String,
        expected: TransmissionTorrentDetail
    ) async -> Bool {
        guard let client, !isBusy, expected.id > 0,
              torrents.contains(where: { $0.id == expected.id }) else {
            errorMessage = TransmissionRPCError.invalidTorrentSelection.localizedDescription
            return false
        }

        let ticket = connectionGeneration
        isBusy = true
        mutationGeneration &+= 1
        var mutationStarted = false
        defer {
            if connectionGeneration == ticket { isBusy = false }
        }

        do {
            let location = try RemoteTorrentPath.destination(destination)
            let previous = try RemoteTorrentPath.destination(expected.downloadDir ?? "")
            guard location != previous else {
                throw TransmissionRPCError.invalidRemotePath
            }
            _ = try await confirmedRemoteSnapshot(expected: expected, client: client)
            guard connectionGeneration == ticket else { return false }
            mutationStarted = true
            try await client.moveTorrent(torrentID: expected.id, destination: location)
            guard connectionGeneration == ticket else { return false }
            let verified = try await client.torrentDetails(id: expected.id)
            guard connectionGeneration == ticket else { return false }
            guard verified?.hashString == expected.hashString,
                  verified?.downloadDir == location else {
                throw TransmissionRPCError.remoteStateChanged
            }
            noticeMessage = "Server move confirmed"
            errorMessage = nil
            await refreshAfterRemoteAction(client: client, ticket: ticket)
            return connectionGeneration == ticket
        } catch {
            guard connectionGeneration == ticket else { return false }
            errorMessage = remoteActionError(error, mutationStarted: mutationStarted)
            noticeMessage = nil
            return false
        }
    }

    public func renameTorrentPath(
        _ path: String,
        to name: String,
        expected: TransmissionTorrentDetail
    ) async -> Bool {
        guard let client, !isBusy, expected.id > 0,
              torrents.contains(where: { $0.id == expected.id }) else {
            errorMessage = TransmissionRPCError.invalidTorrentSelection.localizedDescription
            return false
        }

        let ticket = connectionGeneration
        isBusy = true
        mutationGeneration &+= 1
        var mutationStarted = false
        defer {
            if connectionGeneration == ticket { isBusy = false }
        }

        do {
            let oldPath = try RemoteTorrentPath.relative(path)
            let newName = try RemoteTorrentPath.name(name)
            let parts = oldPath.split(separator: "/")
            let updatedPath = (parts.dropLast().map(String.init) + [newName])
                .joined(separator: "/")
            let snapshotPaths = RemoteTorrentPath.renameCandidates(files: expected.files ?? [])
            guard snapshotPaths.contains(oldPath), oldPath != updatedPath,
                  !snapshotPaths.contains(updatedPath) else {
                throw TransmissionRPCError.remoteStateChanged
            }
            let latest = try await confirmedRemoteSnapshot(expected: expected, client: client)
            guard connectionGeneration == ticket else { return false }
            guard latest.files?.map(\.name) == expected.files?.map(\.name) else {
                throw TransmissionRPCError.remoteStateChanged
            }

            mutationStarted = true
            try await client.renameTorrentPath(
                torrentID: expected.id, path: oldPath, name: newName
            )
            guard connectionGeneration == ticket else { return false }
            let verified = try await client.torrentDetails(id: expected.id)
            guard connectionGeneration == ticket else { return false }
            let paths = RemoteTorrentPath.renameCandidates(files: verified?.files ?? [])
            guard verified?.hashString == expected.hashString,
                  paths.contains(updatedPath), !paths.contains(oldPath) else {
                throw TransmissionRPCError.remoteStateChanged
            }
            noticeMessage = "Server path rename confirmed"
            errorMessage = nil
            await refreshAfterRemoteAction(client: client, ticket: ticket)
            return connectionGeneration == ticket
        } catch {
            guard connectionGeneration == ticket else { return false }
            errorMessage = remoteActionError(error, mutationStarted: mutationStarted)
            noticeMessage = nil
            return false
        }
    }

    private func remoteActionError(_ error: Error, mutationStarted: Bool) -> String {
        guard mutationStarted else { return error.localizedDescription }
        if let remoteError = error as? TransmissionRPCError {
            switch remoteError {
            case .serverError(_), .unauthorized:
                return remoteError.localizedDescription
            default:
                break
            }
        }
        return TransmissionRPCError.remoteMutationUnverified.localizedDescription
    }

    private func confirmedRemoteSnapshot(
        expected: TransmissionTorrentDetail,
        client: any TransmissionRPCProviding
    ) async throws -> TransmissionTorrentDetail {
        guard expected.id > 0,
              let hash = expected.hashString, !hash.isEmpty,
              let current = try await client.torrentDetails(id: expected.id),
              current.id == expected.id,
              current.hashString == hash,
              current.downloadDir == expected.downloadDir else {
            throw TransmissionRPCError.remoteStateChanged
        }
        return current
    }

    private func refreshAfterRemoteAction(
        client: any TransmissionRPCProviding, ticket: UInt64
    ) async {
        // A successful RPC has already happened; a failed refresh must never
        // turn the completed remote mutation into an apparent failed command.
        do {
            let loaded = try await client.torrents()
            guard connectionGeneration == ticket else { return }
            torrents = loaded
            selectedTorrentIDs.formIntersection(Set(loaded.map(\.id)))
            await loadSelectedTorrentDetails()
        } catch {
            // Automatic polling can retry the non-destructive display refresh.
        }
    }

    public func magnetLink(for id: Int) async -> String? {
        guard let client, id > 0, torrents.contains(where: { $0.id == id }) else {
            errorMessage = TransmissionRPCError.invalidTorrentSelection.localizedDescription
            return nil
        }
        let ticket = connectionGeneration
        do {
            let link = try await client.magnetLink(id: id)
            guard connectionGeneration == ticket else { return nil }
            guard let link, link.hasPrefix("magnet:?") else {
                noticeMessage = "This torrent has no magnet link available"
                return nil
            }
            return link
        } catch {
            guard connectionGeneration == ticket else { return nil }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public func addTorrent(
        _ source: TorrentAddSource,
        startImmediately: Bool
    ) async {
        guard let client, !isBusy else { return }
        mutationGeneration &+= 1
        let generation = connectionGeneration
        isBusy = true
        defer {
            if connectionGeneration == generation {
                isBusy = false
            }
        }

        do {
            let outcome = try await client.addTorrent(
                source, startImmediately: startImmediately
            )
            guard connectionGeneration == generation else { return }

            let loaded = try await client.torrents()
            guard connectionGeneration == generation else { return }

            torrents = loaded
            selectedTorrentIDs.formIntersection(Set(loaded.map(\.id)))
            errorMessage = nil
            switch outcome {
            case .added(let torrent):
                noticeMessage = "Added: \(torrent.name)"
            case .duplicate(let torrent):
                noticeMessage = "Already exists: \(torrent.name)"
            }
        } catch {
            guard connectionGeneration == generation else { return }
            noticeMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    public func disconnect() {
        // Discard pending network replies, including those from earlier connections.
        connectionGeneration &+= 1
        client = nil
        server = nil
        torrents = []
        swarmCounts = [:]
        isRefreshingSwarm = false
        lastRefreshAt = nil
        detailGeneration &+= 1
        editingFileSelectionForID = nil
        selectedTorrentDetail = nil
        detailErrorMessage = nil
        isLoadingDetail = false
        selectedTorrentIDs = []
        errorMessage = nil
        noticeMessage = nil
        password = ""
        strictQueueTorrentIDs = []
        strictQueuePendingIDs = []
        isBusy = false
        isRefreshing = false
        mutationGeneration &+= 1
    }
}
