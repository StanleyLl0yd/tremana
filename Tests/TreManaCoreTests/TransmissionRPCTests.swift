import Foundation
import Testing
@testable import TreManaCore

@Suite("Transmission 3.00 RPC", .serialized)
struct TransmissionRPCTests {
    @Test func sessionHandshakeAndTorrentList() async throws {
        MockURLProtocol.responses.replace([
            MockResponse(status: 409, headers: [
                "X-Transmission-Session-Id": "csrf-token"
            ]),
            MockResponse(body: #"{"result":"success","arguments":{"version":"3.00","rpc-version":16}}"#),
            MockResponse(body: #"{"result":"success","arguments":{"torrents":[{"id":7,"name":"sample","status":4,"percentDone":0.5,"rateDownload":1024,"rateUpload":0,"sizeWhenDone":8192,"eta":8,"errorString":""}]}}"#)
        ])
        let client = try makeClient()
        let info = try await client.sessionInfo()
        let torrents = try await client.torrents()

        #expect(info.version == "3.00")
        #expect(info.rpcVersion == 16)
        #expect(!info.capabilities.supportsSequentialPieces)
        #expect(torrents.count == 1)
        #expect(torrents.first?.name == "sample")
        #expect(torrents.first?.statusDescription == "Downloading")
        #expect(MockURLProtocol.responses.observedSessionIDs == [nil, "csrf-token", "csrf-token"])
    }

    @Test func missingCSRFTokenFailsClosed() async throws {
        MockURLProtocol.responses.replace([MockResponse(status: 409)])
        let client = try makeClient()
        do {
            _ = try await client.sessionInfo()
            Issue.record("Expected handshake failure")
        } catch let error as TransmissionRPCError {
            #expect(error == .sessionHandshakeFailed)
        }
    }

    @Test func authenticationFailuresDoNotRetry() async throws {
        MockURLProtocol.responses.replace([MockResponse(status: 401)])
        let client = try makeClient()
        do {
            _ = try await client.sessionInfo()
            Issue.record("Expected authentication failure")
        } catch let error as TransmissionRPCError {
            #expect(error == .unauthorized)
        }
        #expect(MockURLProtocol.responses.requestCount == 1)
    }

    @Test func rejectsUnencryptedHTTPByDefault() throws {
        let url = try #require(URL(string: "http://192.168.1.1:8090/transmission/rpc"))
        #expect(throws: TransmissionRPCError.insecureHTTPRequiresConsent) {
            _ = try TransmissionConnection(url: url)
        }
        _ = try TransmissionConnection(url: url, allowInsecureHTTP: true)
    }

    @Test func rejectsCredentialsEmbeddedInURL() throws {
        let url = try #require(URL(string: "https://admin:secret@example.net/transmission/rpc"))
        #expect(throws: TransmissionRPCError.invalidURL) {
            _ = try TransmissionConnection(url: url)
        }
    }

    @Test func redirectIsNotAccepted() async throws {
        MockURLProtocol.responses.replace([
            MockResponse(status: 302, headers: [
                "Location": "https://other.example/transmission/rpc"
            ])
        ])
        let client = try makeClient()
        do {
            _ = try await client.sessionInfo()
            Issue.record("Expected redirect refusal")
        } catch let error as TransmissionRPCError {
            #expect(error == .unexpectedStatus(302))
        }
        #expect(MockURLProtocol.responses.requestCount == 1)
    }

    @Test func repeatedSessionChallengeFailsClosed() async throws {
        let response = MockResponse(status: 409, headers: [
            "X-Transmission-Session-Id": "never-accepted"
        ])
        MockURLProtocol.responses.replace([response, response, response])
        let client = try makeClient()
        do {
            _ = try await client.sessionInfo()
            Issue.record("Expected handshake failure")
        } catch let error as TransmissionRPCError {
            #expect(error == .sessionHandshakeFailed)
        }
        #expect(MockURLProtocol.responses.requestCount == 3)
    }

    @Test func serverErrorIsNotSwallowed() async throws {
        MockURLProtocol.responses.replace([
            MockResponse(body: #"{"result":"invalid argument","arguments":{}}"#)
        ])
        let client = try makeClient()
        do {
            _ = try await client.sessionInfo()
            Issue.record("Expected server error")
        } catch let error as TransmissionRPCError {
            #expect(error == .serverError("invalid argument"))
        }
    }

    @Test func scalarListFieldsAreRPC16Compatible() async throws {
        MockURLProtocol.responses.replace([
            MockResponse(body: #"{"result":"success","arguments":{"torrents":[{"id":10,"name":"Example","status":4,"percentDone":0.5,"rateDownload":1024,"rateUpload":512,"sizeWhenDone":4096,"eta":60,"errorString":"","addedDate":1700000000,"uploadRatio":1.25,"uploadedEver":10000,"downloadedEver":8000,"totalSize":16384,"leftUntilDone":2048,"peersConnected":8,"peersSendingToUs":3,"peersGettingFromUs":2,"queuePosition":4}]}}"#)
        ])
        let client = try makeClient()
        let torrent = try #require(try await client.torrents().first)
        #expect(torrent.addedDate == 1700000000)
        #expect(torrent.uploadRatio == 1.25)
        #expect(torrent.peersConnected == 8)
        #expect(torrent.queuePosition == 4)
        let arguments = try #require(
            MockURLProtocol.responses.lastRequest?["arguments"] as? [String: Any]
        )
        let fields = try #require(arguments["fields"] as? [String])
        #expect(fields.contains("addedDate"))
        #expect(fields.contains("uploadRatio"))
        #expect(fields.contains("queuePosition"))
        #expect(!fields.contains("trackerStats"))
    }

    @Test func swarmCountsAreTrackerMaximaNotSums() async throws {
        MockURLProtocol.responses.replace([
            MockResponse(body: #"{"result":"success","arguments":{"torrents":[{"id":1,"trackerStats":[{"seederCount":9,"leecherCount":4},{"seederCount":12,"leecherCount":6},{"seederCount":-1,"leecherCount":-1}]},{"id":2,"trackerStats":[]},{"id":3}]}}"#)
        ])
        let client = try makeClient()
        let counts = try await client.torrentSwarm()
        #expect(counts[1] == TorrentSwarmCounts(seeds: 12, leeches: 6))
        #expect(counts[2] == TorrentSwarmCounts(seeds: nil, leeches: nil))
        #expect(counts[3] == TorrentSwarmCounts(seeds: nil, leeches: nil))
        let request = try #require(MockURLProtocol.responses.lastRequest)
        #expect(request["method"] as? String == "torrent-get")
        let arguments = try #require(request["arguments"] as? [String: Any])
        #expect(arguments["fields"] as? [String] == ["id", "trackerStats"])
        #expect(arguments["ids"] == nil)
    }

    @Test func detailsRequestUsesOnlyOneExplicitTorrentID() async throws {
        MockURLProtocol.responses.replace([
            MockResponse(body: #"{"result":"success","arguments":{"torrents":[{"id":9,"name":"Sample","status":4,"percentDone":0.6,"downloadDir":"/media/torrents","files":[{"name":"video.mkv","length":1024,"bytesCompleted":512}],"fileStats":[{"wanted":true,"priority":0,"bytesCompleted":512}],"peers":[{"address":"192.0.2.1","port":51413,"clientName":"Client","progress":0.5,"rateToClient":4096,"rateToPeer":0}],"trackerStats":[{"host":"tracker.example","announce":"https://tracker.example/announce","tier":1,"seederCount":42,"leecherCount":18,"hasAnnounced":true,"lastAnnounceSucceeded":true,"lastAnnouncePeerCount":12,"lastAnnounceTime":1700000000,"nextAnnounceTime":1700001800,"lastScrapeResult":"Success","lastScrapeTime":1700000010}],"webseeds":["https://cdn.example/file"]}]}}"#)
        ])
        let client = try makeClient()
        let result = try #require(try await client.torrentDetails(id: 9))
        #expect(result.id == 9)
        #expect(result.files?.first?.name == "video.mkv")
        #expect(result.fileStats?.first?.wanted == true)
        #expect(result.peers?.first?.rateToClient == 4096)
        #expect(result.trackerStats?.first?.host == "tracker.example")
        #expect(result.trackerStats?.first?.lastAnnounceSucceeded == true)
        #expect(result.trackerStats?.first?.seederCount == 42)
        #expect(result.trackerStats?.first?.leecherCount == 18)
        #expect(result.trackerStats?.first?.lastAnnouncePeerCount == 12)
        #expect(result.trackerStats?.first?.nextAnnounceTime == 1700001800)
        #expect(result.trackerStats?.first?.lastScrapeResult == "Success")
        #expect(result.webseeds == ["https://cdn.example/file"])

        let request = try #require(MockURLProtocol.responses.lastRequest)
        #expect(request["method"] as? String == "torrent-get")
        let arguments = try #require(request["arguments"] as? [String: Any])
        #expect(arguments["ids"] as? [Int] == [9])
        let fields = try #require(arguments["fields"] as? [String])
        #expect(fields.contains("fileStats"))
        #expect(fields.contains("trackerStats"))
        #expect(fields.contains("peers"))
        #expect(fields.contains("webseeds"))
        #expect(!fields.contains("downloadLimit"))
        #expect(!fields.contains("uploadLimit"))
        #expect(!fields.contains("honorsSessionLimits"))
    }

    @Test func detailsRejectInvalidIDBeforeAnyNetworkRequest() async throws {
        MockURLProtocol.responses.replace([])
        let client = try makeClient()
        for id in [-1, 0] {
            do {
                _ = try await client.torrentDetails(id: id)
                Issue.record("Expected invalid selected torrent ID")
            } catch let error as TransmissionRPCError {
                #expect(error == .invalidTorrentSelection)
            }
        }
        #expect(MockURLProtocol.responses.requestCount == 0)
    }

    @Test func detailsReturnNilForMissingIDWithoutFetchingAll() async throws {
        MockURLProtocol.responses.replace([
            MockResponse(body: #"{"result":"success","arguments":{"torrents":[]}}"#)
        ])
        let client = try makeClient()
        #expect(try await client.torrentDetails(id: 42) == nil)
        let arguments = try #require(
            MockURLProtocol.responses.lastRequest?["arguments"] as? [String: Any]
        )
        #expect(arguments["ids"] as? [Int] == [42])
    }

    @Test(arguments: TorrentAction.allCases)
    func actionsOnlyTargetExplicitTorrentIDs(_ action: TorrentAction) async throws {
        MockURLProtocol.responses.replace([
            MockResponse(body: #"{"result":"success"}"#)
        ])
        let client = try makeClient()

        try await client.perform(action, ids: [9, 1, 9])

        let request = try #require(MockURLProtocol.responses.lastRequest)
        #expect(request["method"] as? String == action.rawValue)
        let arguments = try #require(request["arguments"] as? [String: Any])
        #expect(arguments["ids"] as? [Int] == [1, 9])
        #expect(MockURLProtocol.responses.requestCount == 1)
    }

    @Test func emptyOrInvalidIDsNeverReachTheServer() async throws {
        MockURLProtocol.responses.replace([])
        let client = try makeClient()
        for ids in [[], [0], [-1], [1, 0]] {
            do {
                try await client.perform(.stop, ids: ids)
                Issue.record("Expected refusal for ids: \(ids)")
            } catch let error as TransmissionRPCError {
                #expect(error == .invalidTorrentSelection)
            }
        }
        #expect(MockURLProtocol.responses.requestCount == 0)
    }

    @Test func actionServerErrorsAreNotSwallowed() async throws {
        MockURLProtocol.responses.replace([
            MockResponse(body: #"{"result":"torrent not found"}"#)
        ])
        let client = try makeClient()
        do {
            try await client.perform(.start, ids: [11])
            Issue.record("Expected RPC failure")
        } catch let error as TransmissionRPCError {
            #expect(error == .serverError("torrent not found"))
        }
    }

    @Test(arguments: [false, true])
    func removeUsesExplicitIDsAndDeletionFlag(_ deleteData: Bool) async throws {
        MockURLProtocol.responses.replace([
            MockResponse(body: #"{"result":"success"}"#)
        ])
        let client = try makeClient()
        try await client.removeTorrents(ids: [8, 3, 8], deleteLocalData: deleteData)
        let request = try #require(MockURLProtocol.responses.lastRequest)
        #expect(request["method"] as? String == "torrent-remove")
        let arguments = try #require(request["arguments"] as? [String: Any])
        #expect(arguments["ids"] as? [Int] == [3, 8])
        #expect(arguments["delete-local-data"] as? Bool == deleteData)
        #expect(MockURLProtocol.responses.requestCount == 1)
    }

    @Test func removeRejectsInvalidIDsWithoutContactingServer() async throws {
        MockURLProtocol.responses.replace([])
        let client = try makeClient()
        for invalid in [[], [0], [-1], [0, 10]] {
            do {
                try await client.removeTorrents(ids: invalid, deleteLocalData: true)
                Issue.record("Expected rejection for \(invalid)")
            } catch let error as TransmissionRPCError {
                #expect(error == .invalidTorrentSelection)
            }
        }
        #expect(MockURLProtocol.responses.requestCount == 0)
    }

    @Test func magnetLinkIsFetchedForExactlyOneTorrent() async throws {
        let magnet = "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"
        MockURLProtocol.responses.replace([
            MockResponse(body: #"{"result":"success","arguments":{"torrents":[{"id":7,"magnetLink":"magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"}]}}"#)
        ])
        let client = try makeClient()
        #expect(try await client.magnetLink(id: 7) == magnet)
        let request = try #require(MockURLProtocol.responses.lastRequest)
        #expect(request["method"] as? String == "torrent-get")
        let arguments = try #require(request["arguments"] as? [String: Any])
        #expect(arguments["ids"] as? [Int] == [7])
        #expect(arguments["fields"] as? [String] == ["id", "magnetLink"])
    }

    @Test func magnetLinkRejectsNonPositiveIDs() async throws {
        MockURLProtocol.responses.replace([])
        let client = try makeClient()
        for id in [-1, 0] {
            do {
                _ = try await client.magnetLink(id: id)
                Issue.record("Expected refusal for \(id)")
            } catch let error as TransmissionRPCError {
                #expect(error == .invalidTorrentSelection)
            }
        }
        #expect(MockURLProtocol.responses.requestCount == 0)
    }

    @Test func magnetAddUsesLegacyRPC16Vocabulary() async throws {
        MockURLProtocol.responses.replace([
            MockResponse(body: #"{"result":"success","arguments":{"torrent-added":{"id":17,"name":"Sample","hashString":"0123456789abcdef0123456789abcdef01234567"}}}"#)
        ])
        let client = try makeClient()
        let link = "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Sample"

        let outcome = try await client.addTorrent(.magnet(link), startImmediately: false)

        guard case .added(let torrent) = outcome else {
            Issue.record("Expected torrent-added")
            return
        }
        #expect(torrent.id == 17)
        let request = try #require(MockURLProtocol.responses.lastRequest)
        #expect(request["method"] as? String == "torrent-add")
        let arguments = try #require(request["arguments"] as? [String: Any])
        #expect(arguments["filename"] as? String == link)
        #expect(arguments["paused"] as? Bool == true)
        #expect(arguments["metainfo"] == nil)
    }

    @Test func duplicateMagnetIsReportedAsDuplicate() async throws {
        MockURLProtocol.responses.replace([
            MockResponse(body: #"{"result":"success","arguments":{"torrent-duplicate":{"id":18,"name":"Existing","hashString":"0123456789abcdef0123456789abcdef01234567"}}}"#)
        ])
        let client = try makeClient()
        let outcome = try await client.addTorrent(
            .magnet("magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"),
            startImmediately: true
        )
        guard case .duplicate(let torrent) = outcome else {
            Issue.record("Duplicate wrongly reported as newly added")
            return
        }
        #expect(torrent.name == "Existing")
        let args = try #require(
            MockURLProtocol.responses.lastRequest?["arguments"] as? [String: Any]
        )
        #expect(args["paused"] as? Bool == false)
    }

    @Test func torrentFileUsesBase64MetainfoWithoutLocalPath() async throws {
        MockURLProtocol.responses.replace([
            MockResponse(body: #"{"result":"success","arguments":{"torrent-added":{"id":20,"name":"File","hashString":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}}"#)
        ])
        let client = try makeClient()
        let metadata = Data("d4:infod4:name4:teste".utf8)
        _ = try await client.addTorrent(.metainfo(metadata), startImmediately: false)
        let args = try #require(
            MockURLProtocol.responses.lastRequest?["arguments"] as? [String: Any]
        )
        #expect(args["metainfo"] as? String == metadata.base64EncodedString())
        #expect(args["filename"] == nil)
        #expect(args["paused"] as? Bool == true)
    }

    @Test func invalidTorrentInputNeverHitsRPC() async throws {
        MockURLProtocol.responses.replace([])
        let client = try makeClient()
        let inputs: [TorrentAddSource] = [
            .magnet("http://example.com/file.torrent"),
            .magnet("magnet:?xt=urn:btih:short"),
            .metainfo(Data())
        ]
        for input in inputs {
            do {
                _ = try await client.addTorrent(input, startImmediately: true)
                Issue.record("Expected invalid torrent input")
            } catch let error as TransmissionRPCError {
                #expect(
                    error == .invalidMagnetLink ||
                    error == .invalidTorrentMetainfo
                )
            }
        }
        #expect(MockURLProtocol.responses.requestCount == 0)
    }

    @Test func malformedSuccessfulAddIsRejected() async throws {
        MockURLProtocol.responses.replace([
            MockResponse(body: #"{"result":"success","arguments":{}}"#)
        ])
        let client = try makeClient()
        do {
            _ = try await client.addTorrent(
                .magnet("magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"),
                startImmediately: true
            )
            Issue.record("Expected invalid add response")
        } catch let error as TransmissionRPCError {
            #expect(error == .invalidTorrentAddReply)
        }
    }

    @Test(arguments: [true, false])
    func fileWantedRPCUsesOneExplicitIndex(_ wanted: Bool) async throws {
        MockURLProtocol.responses.replace([
            MockResponse(body: #"{"result":"success"}"#)
        ])
        let client = try makeClient()
        try await client.setFileWanted(torrentID: 7, fileIndex: 2, wanted: wanted)
        let request = try #require(MockURLProtocol.responses.lastRequest)
        #expect(request["method"] as? String == "torrent-set")
        let arguments = try #require(request["arguments"] as? [String: Any])
        #expect(arguments["ids"] as? [Int] == [7])
        let selected = wanted ? "files-wanted" : "files-unwanted"
        let opposite = wanted ? "files-unwanted" : "files-wanted"
        #expect(arguments[selected] as? [Int] == [2])
        #expect(arguments[opposite] == nil)
        #expect(arguments["priority-high"] == nil)
        #expect(arguments["priority-low"] == nil)
        #expect(MockURLProtocol.responses.requestCount == 1)
    }

    @Test func invalidFileSelectionNeverContactsDaemon() async throws {
        MockURLProtocol.responses.replace([])
        let client = try makeClient()
        for id in [0, -1] {
            do {
                try await client.setFileWanted(torrentID: id, fileIndex: 0, wanted: true)
                Issue.record("Expected invalid torrent ID")
            } catch let error as TransmissionRPCError {
                #expect(error == .invalidTorrentSelection)
            }
        }
        do {
            try await client.setFileWanted(torrentID: 7, fileIndex: -1, wanted: false)
            Issue.record("Expected invalid file index")
        } catch let error as TransmissionRPCError {
            #expect(error == .invalidFileSelection)
        }
        #expect(MockURLProtocol.responses.requestCount == 0)
    }

    @Test func fileSelectionRPCFailureIsReported() async throws {
        MockURLProtocol.responses.replace([
            MockResponse(body: #"{"result":"file index invalid"}"#)
        ])
        let client = try makeClient()
        do {
            try await client.setFileWanted(torrentID: 7, fileIndex: 2, wanted: false)
            Issue.record("Expected daemon refusal")
        } catch let error as TransmissionRPCError {
            #expect(error == .serverError("file index invalid"))
        }
        #expect(MockURLProtocol.responses.requestCount == 1)
    }

    private func makeClient() throws -> TransmissionRPCClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let connection = try TransmissionConnection(
            url: URL(string: "https://router.example/transmission/rpc")!
        )
        return TransmissionRPCClient(connection: connection, session: session)
    }
}

private struct MockResponse: Sendable {
    let status: Int
    let headers: [String: String]
    let body: Data

    init(status: Int = 200, headers: [String: String] = [:], body: String = "") {
        self.status = status
        self.headers = headers
        self.body = Data(body.utf8)
    }
}

private final class ResponseQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [MockResponse] = []
    private var seenIDs: [String?] = []
    private var requestBodies: [Data] = []

    func replace(_ responses: [MockResponse]) {
        lock.lock()
        defer { lock.unlock() }
        pending = responses
        seenIDs = []
        requestBodies = []
    }

    func next(request: URLRequest) -> MockResponse {
        lock.lock()
        defer { lock.unlock() }
        seenIDs.append(request.value(forHTTPHeaderField: "X-Transmission-Session-Id"))
        if let data = request.httpBody {
            requestBodies.append(data)
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            if !data.isEmpty { requestBodies.append(data) }
        }
        if pending.isEmpty { return MockResponse(status: 500) }
        return pending.removeFirst()
    }

    var observedSessionIDs: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return seenIDs
    }

    var lastRequest: [String: Any]? {
        lock.lock()
        let last = requestBodies.last
        lock.unlock()
        guard let last else { return nil }
        return try? JSONSerialization.jsonObject(with: last) as? [String: Any]
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return seenIDs.count
    }
}

private final class MockURLProtocol: URLProtocol {
    static let responses = ResponseQueue()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let fixture = Self.responses.next(request: request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: fixture.status,
            httpVersion: "HTTP/1.1",
            headerFields: fixture.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: fixture.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
