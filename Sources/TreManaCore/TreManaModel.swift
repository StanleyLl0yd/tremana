import Foundation
import Observation

public protocol TransmissionRPCProviding: Sendable {
    func sessionInfo() async throws -> TransmissionSession
    func torrents() async throws -> [TransmissionTorrent]
    func perform(_ action: TorrentAction, ids: [Int]) async throws
    func addTorrent(_ source: TorrentAddSource, startImmediately: Bool) async throws -> TorrentAddOutcome
}

extension TransmissionRPCClient: TransmissionRPCProviding {}

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
    public private(set) var errorMessage: String?
    public private(set) var noticeMessage: String?
    public private(set) var profileErrorMessage: String?
    public private(set) var profilesBusy = false
    public private(set) var savedProfiles: [ConnectionProfile] = []
    public private(set) var server: TransmissionSession?
    public private(set) var torrents: [TransmissionTorrent] = []

    @ObservationIgnored
    private let makeClient: @MainActor (TransmissionConnection) -> any TransmissionRPCProviding

    @ObservationIgnored
    private var client: (any TransmissionRPCProviding)?

    @ObservationIgnored
    private var connectionGeneration: UInt64 = 0

    @ObservationIgnored
    private var profileSelectionGeneration: UInt64 = 0

    @ObservationIgnored
    private let profileStore: any ConnectionProfileStoring

    public var isConnected: Bool { server != nil && client != nil }

    public init(
        makeClient: @escaping @MainActor (TransmissionConnection) -> any TransmissionRPCProviding = {
            TransmissionRPCClient(connection: $0)
        },
        profileStore: any ConnectionProfileStoring = UserDefaultsProfileStore()
    ) {
        self.makeClient = makeClient
        self.profileStore = profileStore
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
            selectedTorrentIDs = []
            noticeMessage = nil
            password = ""

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

    public func refresh() async {
        guard let client, !isBusy else { return }
        let generation = connectionGeneration
        isBusy = true
        defer {
            if connectionGeneration == generation {
                isBusy = false
            }
        }

        do {
            let loaded = try await client.torrents()
            guard connectionGeneration == generation else { return }
            torrents = loaded
            selectedTorrentIDs.formIntersection(Set(loaded.map(\.id)))
            errorMessage = nil
        } catch {
            guard connectionGeneration == generation else { return }
            errorMessage = error.localizedDescription
        }
    }

    public func perform(_ action: TorrentAction) async {
        guard let client, !isBusy else { return }
        let availableIDs = Set(torrents.map(\.id))
        let ids = selectedTorrentIDs.intersection(availableIDs).sorted()
        guard !ids.isEmpty else { return }

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
        } catch {
            guard connectionGeneration == generation else { return }
            errorMessage = error.localizedDescription
        }
    }

    public func addTorrent(
        _ source: TorrentAddSource,
        startImmediately: Bool
    ) async {
        guard let client, !isBusy else { return }
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
        selectedTorrentIDs = []
        errorMessage = nil
        noticeMessage = nil
        password = ""
        isBusy = false
    }
}
