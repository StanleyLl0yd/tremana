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

    public private(set) var isBusy = false
    public private(set) var errorMessage: String?
    public private(set) var noticeMessage: String?
    public private(set) var server: TransmissionSession?
    public private(set) var torrents: [TransmissionTorrent] = []

    @ObservationIgnored
    private let makeClient: @MainActor (TransmissionConnection) -> any TransmissionRPCProviding

    @ObservationIgnored
    private var client: (any TransmissionRPCProviding)?

    @ObservationIgnored
    private var connectionGeneration: UInt64 = 0

    public var isConnected: Bool { server != nil && client != nil }

    public init(
        makeClient: @escaping @MainActor (TransmissionConnection) -> any TransmissionRPCProviding = {
            TransmissionRPCClient(connection: $0)
        }
    ) {
        self.makeClient = makeClient
    }

    public func connect() async {
        guard !isBusy, !isConnected else { return }
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
            let credentials: RPCBasicCredentials? = username.isEmpty
                ? nil
                : RPCBasicCredentials(username: username, password: password)
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
