import Foundation

public enum TransmissionRPCError: Error, LocalizedError, Equatable, Sendable {
    case invalidURL
    case insecureHTTPRequiresConsent
    case unauthorized
    case sessionHandshakeFailed
    case unexpectedStatus(Int)
    case serverError(String)
    case missingArguments
    case unsupportedRPCVersion(Int)
    case invalidTorrentSelection
    case invalidFileSelection
    case lastWantedFile
    case fileSelectionChanged
    case invalidMagnetLink
    case invalidTorrentMetainfo
    case invalidTorrentAddReply

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Enter a valid HTTP or HTTPS RPC URL without embedded credentials."
        case .insecureHTTPRequiresConsent:
            "HTTP is unencrypted. Explicitly enable HTTP for a trusted local connection."
        case .unauthorized:
            "Transmission rejected the username or password."
        case .sessionHandshakeFailed:
            "Unable to negotiate the Transmission RPC session."
        case .unexpectedStatus(let code):
            "Transmission returned HTTP \(code)."
        case .serverError(let reason):
            "Transmission RPC error: \(reason)."
        case .missingArguments:
            "Transmission returned an incomplete RPC response."
        case .unsupportedRPCVersion(let version):
            "RPC version \(version) is not yet supported. TreMana currently supports RPC 16 and 17."
        case .invalidTorrentSelection:
            "Select one or more valid torrents. Refusing an operation that could affect all torrents."
        case .invalidFileSelection:
            "File metadata is missing or the selected file index is invalid. No changes were made."
        case .lastWantedFile:
            "At least one file must remain selected for download."
        case .fileSelectionChanged:
            "File selection changed on the server. Refresh and try again."
        case .invalidMagnetLink:
            "Enter a valid BitTorrent v1 magnet link with an info hash."
        case .invalidTorrentMetainfo:
            "The .torrent file must contain between 1 byte and 16 MiB of data."
        case .invalidTorrentAddReply:
            "Transmission returned success without identifying the added or existing torrent."
        }
    }
}

public struct RPCBasicCredentials: Sendable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public struct TransmissionConnection: Sendable {
    public let url: URL
    public let credentials: RPCBasicCredentials?

    public init(
        url: URL,
        credentials: RPCBasicCredentials? = nil,
        allowInsecureHTTP: Bool = false
    ) throws {
        guard let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil,
              url.user == nil,
              url.password == nil,
              url.fragment == nil else {
            throw TransmissionRPCError.invalidURL
        }
        if scheme == "http" && !allowInsecureHTTP {
            throw TransmissionRPCError.insecureHTTPRequiresConsent
        }
        self.url = url
        self.credentials = credentials
    }
}

private final class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = RejectRedirects()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public actor TransmissionRPCClient {
    private let connection: TransmissionConnection
    private let session: URLSession
    private var sessionID: String?

    public init(connection: TransmissionConnection, session: URLSession = .shared) {
        self.connection = connection
        self.session = session
    }

    public func sessionInfo() async throws -> TransmissionSession {
        let response: TransmissionSession = try await call("session-get")
        guard (16...17).contains(response.rpcVersion) else {
            throw TransmissionRPCError.unsupportedRPCVersion(response.rpcVersion)
        }
        return response
    }

    public func torrents() async throws -> [TransmissionTorrent] {
        let fields = [
            "id", "name", "status", "percentDone", "rateDownload",
            "rateUpload", "sizeWhenDone", "eta", "errorString",
            "addedDate", "doneDate", "uploadRatio", "uploadedEver",
            "downloadedEver", "totalSize", "leftUntilDone", "peersConnected",
            "peersSendingToUs", "peersGettingFromUs", "queuePosition"
        ]
        let response: TorrentList = try await call(
            "torrent-get",
            arguments: ["fields": .array(fields.map { .string($0) })]
        )
        return response.torrents
    }

    public func torrentSwarm() async throws -> [Int: TorrentSwarmCounts] {
        // Tracker stats are much larger than scalar fields. Poll separately.
        let response: TorrentSwarmList = try await call(
            "torrent-get",
            arguments: [
                "fields": .array([.string("id"), .string("trackerStats")])
            ]
        )
        var result: [Int: TorrentSwarmCounts] = [:]
        for torrent in response.torrents where torrent.id > 0 {
            result[torrent.id] = torrent.counts
        }
        return result
    }

    public func torrentDetails(id: Int) async throws -> TransmissionTorrentDetail? {
        // Legacy Transmission treats omitted/empty IDs as ALL torrents.
        guard id > 0 else { throw TransmissionRPCError.invalidTorrentSelection }
        let fields = [
            "id", "name", "status", "percentDone", "totalSize", "sizeWhenDone",
            "downloadedEver", "uploadedEver", "leftUntilDone", "uploadRatio",
            "rateDownload", "rateUpload", "eta", "downloadDir", "hashString",
            "comment", "creator", "dateCreated", "addedDate", "doneDate",
            "activityDate", "secondsDownloading", "secondsSeeding",
            "peersConnected", "peersSendingToUs", "peersGettingFromUs",
            "files", "fileStats", "trackers", "trackerStats", "peers",
            "webseeds", "errorString"
        ]
        let response: TransmissionTorrentDetailList = try await call(
            "torrent-get",
            arguments: [
                "ids": .array([.integer(id)]),
                "fields": .array(fields.map { .string($0) })
            ]
        )
        return response.torrents.first(where: { $0.id == id })
    }

    public func perform(_ action: TorrentAction, ids: [Int]) async throws {
        // Legacy Transmission interprets missing or empty ids as ALL torrents.
        guard !ids.isEmpty, ids.allSatisfy({ $0 > 0 }) else {
            throw TransmissionRPCError.invalidTorrentSelection
        }
        let ids = Array(Set(ids)).sorted()
        let _: RPCReply<EmptyRPCArguments> = try await send(
            action.rawValue,
            arguments: ["ids": .array(ids.map { .integer($0) })]
        )
    }

    public func setFileWanted(
        torrentID: Int,
        fileIndex: Int,
        wanted: Bool
    ) async throws {
        guard torrentID > 0 else {
            throw TransmissionRPCError.invalidTorrentSelection
        }
        guard fileIndex >= 0 else {
            throw TransmissionRPCError.invalidFileSelection
        }

        // Each RPC changes exactly one 0-based file index. Never pass an empty
        // file array, which legacy Transmission can interpret as all files.
        let field = wanted ? "files-wanted" : "files-unwanted"
        let _: RPCReply<EmptyRPCArguments> = try await send(
            "torrent-set",
            arguments: [
                "ids": .array([.integer(torrentID)]),
                field: .array([.integer(fileIndex)])
            ]
        )
    }

    public func magnetLink(id: Int) async throws -> String? {
        guard id > 0 else { throw TransmissionRPCError.invalidTorrentSelection }
        let reply: TorrentMagnetList = try await call(
            "torrent-get",
            arguments: [
                "ids": .array([.integer(id)]),
                "fields": .array([.string("id"), .string("magnetLink")])
            ]
        )
        return reply.torrents.first(where: { $0.id == id })?.magnetLink
    }

    public func removeTorrents(ids: [Int], deleteLocalData: Bool) async throws {
        guard !ids.isEmpty, ids.allSatisfy({ $0 > 0 }) else {
            throw TransmissionRPCError.invalidTorrentSelection
        }
        let unique = Array(Set(ids)).sorted()
        let _: RPCReply<EmptyRPCArguments> = try await send(
            "torrent-remove",
            arguments: [
                "ids": .array(unique.map { .integer($0) }),
                "delete-local-data": .boolean(deleteLocalData)
            ]
        )
    }

    public func addTorrent(
        _ source: TorrentAddSource,
        startImmediately: Bool
    ) async throws -> TorrentAddOutcome {
        var arguments: [String: RPCValue] = [
            "paused": .boolean(!startImmediately)
        ]

        switch source {
        case .magnet(let input):
            let magnet = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard magnet.utf8.count <= 16_384,
                  let components = URLComponents(string: magnet),
                  components.scheme?.lowercased() == "magnet",
                  components.queryItems?.contains(where: { item in
                      guard item.name.lowercased() == "xt",
                            let value = item.value,
                            value.lowercased().hasPrefix("urn:btih:") else {
                          return false
                      }
                      let hash = String(value.dropFirst(9))
                      if hash.count == 40 {
                          return hash.allSatisfy {
                              "0123456789abcdefABCDEF".contains($0)
                          }
                      }
                      if hash.count == 32 {
                          return hash.uppercased().allSatisfy {
                              "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".contains($0)
                          }
                      }
                      return false
                  }) == true else {
                throw TransmissionRPCError.invalidMagnetLink
            }
            arguments["filename"] = .string(magnet)

        case .metainfo(let data):
            guard !data.isEmpty, data.count <= 16 * 1024 * 1024 else {
                throw TransmissionRPCError.invalidTorrentMetainfo
            }
            arguments["metainfo"] = .string(data.base64EncodedString())
        }

        let response: TorrentAddArguments = try await call(
            "torrent-add", arguments: arguments
        )
        if let added = response.added {
            return .added(added)
        }
        if let duplicate = response.duplicate {
            return .duplicate(duplicate)
        }
        throw TransmissionRPCError.invalidTorrentAddReply
    }

    private func call<Value: Decodable>(
        _ method: String,
        arguments: [String: RPCValue] = [:]
    ) async throws -> Value {
        let reply: RPCReply<Value> = try await send(method, arguments: arguments)
        guard let arguments = reply.arguments else {
            throw TransmissionRPCError.missingArguments
        }
        return arguments
    }

    private func send<Value: Decodable>(
        _ method: String,
        arguments: [String: RPCValue]
    ) async throws -> RPCReply<Value> {
        let body = try JSONEncoder().encode(
            RPCRequest(method: method, arguments: arguments)
        )

        for _ in 0..<3 {
            var request = URLRequest(url: connection.url)
            request.httpMethod = "POST"
            request.httpBody = body
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("TreMana/0.1", forHTTPHeaderField: "User-Agent")
            if let sessionID {
                request.setValue(sessionID, forHTTPHeaderField: "X-Transmission-Session-Id")
            }
            if let credentials = connection.credentials {
                let encoded = Data(
                    "\(credentials.username):\(credentials.password)".utf8
                ).base64EncodedString()
                request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await session.data(
                for: request, delegate: RejectRedirects.shared
            )
            guard let response = response as? HTTPURLResponse else {
                throw TransmissionRPCError.sessionHandshakeFailed
            }

            if response.statusCode == 409 {
                guard let token = response.value(
                    forHTTPHeaderField: "X-Transmission-Session-Id"
                ), !token.isEmpty else {
                    throw TransmissionRPCError.sessionHandshakeFailed
                }
                sessionID = token
                continue
            }
            if response.statusCode == 401 || response.statusCode == 403 {
                throw TransmissionRPCError.unauthorized
            }
            guard (200...299).contains(response.statusCode) else {
                throw TransmissionRPCError.unexpectedStatus(response.statusCode)
            }

            let decoded = try JSONDecoder().decode(RPCReply<Value>.self, from: data)
            guard decoded.result == "success" else {
                throw TransmissionRPCError.serverError(decoded.result)
            }
            return decoded
        }

        throw TransmissionRPCError.sessionHandshakeFailed
    }
}


private struct TorrentMagnetList: Decodable {
    let torrents: [TorrentMagnetItem]
}

private struct TorrentMagnetItem: Decodable {
    let id: Int
    let magnetLink: String?
}
