import Foundation

public struct TransmissionSession: Decodable, Sendable {
    public let version: String
    public let rpcVersion: Int

    enum CodingKeys: String, CodingKey {
        case version
        case rpcVersion = "rpc-version"
    }

    public var capabilities: TransmissionCapabilities {
        TransmissionCapabilities(rpcVersion: rpcVersion)
    }
}

public struct TransmissionCapabilities: Sendable, Equatable {
    public let rpcVersion: Int

    public init(rpcVersion: Int) {
        self.rpcVersion = rpcVersion
    }

    public var supportsLegacyRPC: Bool { (16...17).contains(rpcVersion) }

    // Transmission 3.00 does not expose sequential piece download over RPC.
    // Newer RPC protocols require a separate adapter before enabling the feature.
    public var supportsSequentialPieces: Bool { false }

    // The server exposes files-wanted/files-unwanted, but an autonomous
    // strict queue controller is not yet implemented in TreMana.
    public var supportsFileSelection: Bool { supportsLegacyRPC }
    public var hasStrictFileQueueController: Bool { false }
}

public struct TransmissionTorrent: Decodable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let status: Int
    public let percentDone: Double
    public let rateDownload: Int64
    public let rateUpload: Int64
    public let sizeWhenDone: Int64
    public let eta: Int
    public let errorString: String

    public var statusDescription: String {
        switch status {
        case 0: "Stopped"
        case 1, 2: "Verifying"
        case 3: "Queued to download"
        case 4: "Downloading"
        case 5: "Queued to seed"
        case 6: "Seeding"
        default: "Unknown"
        }
    }
}

struct TorrentList: Decodable {
    let torrents: [TransmissionTorrent]
}
