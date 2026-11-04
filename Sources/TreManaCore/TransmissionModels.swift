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

    // TreMana advances selected files using files-wanted/files-unwanted.
    // While the Mac is asleep or the application is closed, the next file waits.
    public var supportsFileSelection: Bool { supportsLegacyRPC }
    public var hasStrictFileQueueController: Bool { supportsLegacyRPC }
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
    public let addedDate: Int?
    public let doneDate: Int?
    public let uploadRatio: Double?
    public let uploadedEver: Int64?
    public let downloadedEver: Int64?
    public let totalSize: Int64?
    public let leftUntilDone: Int64?
    public let peersConnected: Int?
    public let peersSendingToUs: Int?
    public let peersGettingFromUs: Int?
    public let queuePosition: Int?
    public let errorString: String

    public init(
        id: Int,
        name: String,
        status: Int,
        percentDone: Double,
        rateDownload: Int64,
        rateUpload: Int64,
        sizeWhenDone: Int64,
        eta: Int,
        errorString: String,
        addedDate: Int? = nil,
        doneDate: Int? = nil,
        uploadRatio: Double? = nil,
        uploadedEver: Int64? = nil,
        downloadedEver: Int64? = nil,
        totalSize: Int64? = nil,
        leftUntilDone: Int64? = nil,
        peersConnected: Int? = nil,
        peersSendingToUs: Int? = nil,
        peersGettingFromUs: Int? = nil,
        queuePosition: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.percentDone = percentDone
        self.rateDownload = rateDownload
        self.rateUpload = rateUpload
        self.sizeWhenDone = sizeWhenDone
        self.eta = eta
        self.errorString = errorString
        self.addedDate = addedDate
        self.doneDate = doneDate
        self.uploadRatio = uploadRatio
        self.uploadedEver = uploadedEver
        self.downloadedEver = downloadedEver
        self.totalSize = totalSize
        self.leftUntilDone = leftUntilDone
        self.peersConnected = peersConnected
        self.peersSendingToUs = peersSendingToUs
        self.peersGettingFromUs = peersGettingFromUs
        self.queuePosition = queuePosition
    }

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


/// Tracker-reported swarm totals. Do not sum across trackers: duplicate peers.
public struct TorrentSwarmCounts: Sendable, Equatable {
    public let seeds: Int?
    public let leeches: Int?

    public init(seeds: Int?, leeches: Int?) {
        self.seeds = seeds
        self.leeches = leeches
    }
}

struct TorrentSwarmList: Decodable {
    let torrents: [TorrentSwarmRecord]
}

struct TorrentSwarmRecord: Decodable {
    let id: Int
    let trackerStats: [TorrentSwarmTracker]?

    var counts: TorrentSwarmCounts {
        let seeds = trackerStats?.compactMap { value -> Int? in
            guard let count = value.seederCount, count >= 0 else { return nil }
            return count
        }.max()
        let leeches = trackerStats?.compactMap { value -> Int? in
            guard let count = value.leecherCount, count >= 0 else { return nil }
            return count
        }.max()
        return TorrentSwarmCounts(seeds: seeds, leeches: leeches)
    }
}

struct TorrentSwarmTracker: Decodable {
    let seederCount: Int?
    let leecherCount: Int?
}
