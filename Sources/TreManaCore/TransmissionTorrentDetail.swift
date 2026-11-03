import Foundation

// Transmission 3.00 / RPC 16 fields are intentionally optional except identity.
// Metadata may be incomplete for magnet transfers.
public struct TransmissionTorrentDetail: Decodable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let status: Int
    public let percentDone: Double?
    public let totalSize: Int64?
    public let sizeWhenDone: Int64?
    public let downloadedEver: Int64?
    public let uploadedEver: Int64?
    public let leftUntilDone: Int64?
    public let uploadRatio: Double?
    public let rateDownload: Int64?
    public let rateUpload: Int64?
    public let eta: Int?
    public let downloadDir: String?
    public let hashString: String?
    public let comment: String?
    public let creator: String?
    public let dateCreated: Int?
    public let addedDate: Int?
    public let doneDate: Int?
    public let activityDate: Int?
    public let secondsDownloading: Int?
    public let secondsSeeding: Int?
    public let peersConnected: Int?
    public let peersSendingToUs: Int?
    public let peersGettingFromUs: Int?
    public let files: [TransmissionTorrentFile]?
    public let fileStats: [TransmissionTorrentFileStat]?
    public let trackers: [TransmissionTorrentTracker]?
    public let trackerStats: [TransmissionTorrentTrackerStat]?
    public let peers: [TransmissionTorrentPeer]?
    public let webseeds: [String]?
    public let downloadLimit: Int?
    public let uploadLimit: Int?
    public let downloadLimited: Bool?
    public let uploadLimited: Bool?
    public let honorsSessionLimits: Bool?
    public let errorString: String?
}

public struct TransmissionTorrentFile: Decodable, Sendable {
    public let name: String
    public let length: Int64
    public let bytesCompleted: Int64
}

public struct TransmissionTorrentFileStat: Decodable, Sendable {
    public let wanted: Bool
    public let priority: Int
    public let bytesCompleted: Int64?
}

public struct TransmissionTorrentTracker: Decodable, Sendable {
    public let id: Int?
    public let announce: String?
    public let scrape: String?
    public let tier: Int?
}

public struct TransmissionTorrentTrackerStat: Decodable, Sendable {
    public let id: Int?
    public let host: String?
    public let announce: String?
    public let announceState: Int?
    public let lastAnnounceResult: String?
    public let lastAnnounceTime: Int?
    public let nextAnnounceTime: Int?
    public let seederCount: Int?
    public let leecherCount: Int?
    public let downloadCount: Int?
}

public struct TransmissionTorrentPeer: Decodable, Sendable {
    public let address: String
    public let port: Int?
    public let clientName: String?
    public let progress: Double?
    public let rateToClient: Int64?
    public let rateToPeer: Int64?
    public let flagStr: String?
    public let isEncrypted: Bool?
}

struct TransmissionTorrentDetailList: Decodable {
    let torrents: [TransmissionTorrentDetail]
}
