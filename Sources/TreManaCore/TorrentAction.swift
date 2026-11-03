import Foundation

public enum TorrentAction: String, CaseIterable, Sendable {
    case start = "torrent-start"
    case stop = "torrent-stop"
    case verify = "torrent-verify"
}

struct EmptyRPCArguments: Decodable {}
