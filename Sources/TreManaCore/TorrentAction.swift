import Foundation

public enum TorrentAction: String, CaseIterable, Sendable {
    case start = "torrent-start"
    case startNow = "torrent-start-now"
    case reannounce = "torrent-reannounce"
    case stop = "torrent-stop"
    case verify = "torrent-verify"
}

struct EmptyRPCArguments: Decodable {}
