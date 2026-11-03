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
            "rateUpload", "sizeWhenDone", "eta", "errorString"
        ]
        let response: TorrentList = try await call(
            "torrent-get",
            arguments: ["fields": .array(fields.map { .string($0) })]
        )
        return response.torrents
    }

    private func call<Value: Decodable>(
        _ method: String,
        arguments: [String: RPCValue] = [:]
    ) async throws -> Value {
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
            guard let arguments = decoded.arguments else {
                throw TransmissionRPCError.missingArguments
            }
            return arguments
        }

        throw TransmissionRPCError.sessionHandshakeFailed
    }
}
