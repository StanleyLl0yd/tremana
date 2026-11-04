import Foundation

/// Validates server paths without interpreting them as macOS or URL paths.
public enum RemoteTorrentPath {
    public static func destination(_ path: String) throws -> String {
        guard path.hasPrefix("/"), path != "/", !path.hasPrefix("//"),
              path == path.trimmingCharacters(in: .whitespacesAndNewlines),
              validSegments(path.dropFirst().split(
                  separator: "/", omittingEmptySubsequences: false
              )) else {
            throw TransmissionRPCError.invalidRemotePath
        }
        return path
    }

    public static func relative(_ path: String) throws -> String {
        guard !path.hasPrefix("/"),
              path == path.trimmingCharacters(in: .whitespacesAndNewlines),
              validSegments(path.split(
                  separator: "/", omittingEmptySubsequences: false
              )) else {
            throw TransmissionRPCError.invalidRemotePath
        }
        return path
    }

    public static func name(_ value: String) throws -> String {
        guard validComponent(Substring(value)),
              value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw TransmissionRPCError.invalidRenameName
        }
        return value
    }

    /// Offer only paths present in the current torrent metadata.
    /// Ancestor folders can be renamed as well as individual files.
    public static func renameCandidates(files: [TransmissionTorrentFile]) -> [String] {
        var result = Set<String>()
        for file in files {
            guard (try? relative(file.name)) != nil else { continue }
            let components = file.name.split(separator: "/")
            for count in 1...components.count {
                result.insert(components.prefix(count).joined(separator: "/"))
            }
        }
        return result.sorted()
    }

    private static func validSegments(_ segments: [Substring]) -> Bool {
        !segments.isEmpty && segments.allSatisfy(validComponent)
    }

    private static func validComponent(_ component: Substring) -> Bool {
        !component.isEmpty && component != "." && component != ".."
            && !component.contains("\\")
            && !component.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0)
            }
    }
}
