import Foundation
import Observation
import TreManaCore

@MainActor
@Observable
final class TreManaModel {
    var rpcURL = "http://192.168.1.1:8090/transmission/rpc"
    var username = ""
    var password = ""
    var allowsInsecureHTTP = false
    var isBusy = false
    var errorMessage: String?
    private(set) var server: TransmissionSession?
    private(set) var torrents: [TransmissionTorrent] = []
    private var client: TransmissionRPCClient?

    var isConnected: Bool { server != nil && client != nil }

    func connect() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
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
            let newClient = TransmissionRPCClient(connection: connection)
            let info = try await newClient.sessionInfo()
            let loaded = try await newClient.torrents()
            server = info
            client = newClient
            torrents = loaded
            password = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        guard let client, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            torrents = try await client.torrents()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        client = nil
        server = nil
        torrents = []
        errorMessage = nil
    }
}
