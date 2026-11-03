import Foundation

public enum TorrentAddSource: Sendable {
    case magnet(String)
    case metainfo(Data)
}

public struct TransmissionAddedTorrent: Decodable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let hashString: String
}

public enum TorrentAddOutcome: Equatable, Sendable {
    case added(TransmissionAddedTorrent)
    case duplicate(TransmissionAddedTorrent)
}

struct TorrentAddArguments: Decodable {
    let added: TransmissionAddedTorrent?
    let duplicate: TransmissionAddedTorrent?

    enum CodingKeys: String, CodingKey {
        case added = "torrent-added"
        case duplicate = "torrent-duplicate"
    }
}
