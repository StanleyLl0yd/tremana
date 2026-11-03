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
            savedProfiles = try await profileStore.list()
            profileErrorMessage = nil
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
            rememberPassword = stored != nil
        } catch {
            guard profileSelectionGeneration == generation else { return }
            profileErrorMessage = error.localizedDescription
        }
    }

    public func saveCurrentProfile() async {
        guard !profilesBusy else { return }
        profilesBusy = true
        defer { profilesBusy = false }

        do {
            let id = selectedProfileID ?? UUID()
            let profile = ConnectionProfile(
                id: id,
                name: profileName,
                rpcURL: rpcURL,
                username: username,
                allowsInsecureHTTP: allowsInsecureHTTP
            )
            let update: ProfilePasswordUpdate
            if rememberPassword {
                guard !username.isEmpty else {
                    throw ProfileStorageError.passwordRequired
                }
                if !password.isEmpty {
                    update = .replace(password)
                } else {
                    guard let previous = savedProfiles.first(where: { $0.id == id }),
                          previous.rpcURL == rpcURL,
                          previous.username == username,
                          previous.allowsInsecureHTTP == allowsInsecureHTTP else {
                        throw ProfileStorageError.passwordRequired
                    }
                    update = .keep
                }
            } else {
                update = .remove
            }

            try await profileStore.save(profile, password: update)
            savedProfiles = try await profileStore.list()
            selectedProfileID = id
            profileErrorMessage = nil
            password = ""
        } catch {
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

        do {
            guard let url = URL(string: rpcURL) else {
                throw TransmissionRPCError.invalidURL
            }
            let saved = savedProfiles.first(where: { $0.id == selectedProfileID })
            let sameEndpoint = saved?.rpcURL == rpcURL
                && saved?.username == username
                && saved?.allowsInsecureHTTP == allowsInsecureHTTP
            var effectivePassword = password
            if effectivePassword.isEmpty,
               sameEndpoint, rememberPassword,
               let selectedProfileID, !username.isEmpty {
                effectivePassword = try await profileStore.password(for: selectedProfileID) ?? ""
                guard connectionGeneration == generation else { return }
            }
            let credentials: RPCBasicCredentials? = username.isEmpty
                ? nil
                : RPCBasicCredentials(username: username, password: effectivePassword)
            let connection = try TransmissionConnection(
                url: url,
                credentials: credentials,
                allowInsecureHTTP: allowsInsecureHTTP
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
