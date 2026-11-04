import Foundation

@MainActor
public final class StrictFileQueueController {
    private static let key = "com.sl.tremana.strict-file-queues.v1"

    private let defaults: UserDefaults
    private var records: [StrictQueueRecord] = []
    private var processing = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([StrictQueueRecord].self, from: data) {
            records = decoded
        }
    }

    public func forgetRemovedTorrents(endpoint: String, ids: Set<Int>) throws {
        try save(records.filter {
            $0.endpoint != endpoint || !ids.contains($0.torrentID)
        })
    }

    public func enabledTorrentIDs(endpoint: String) -> Set<Int> {
        Set(records.filter { $0.endpoint == endpoint }.map(\.torrentID))
    }

    private func save(_ updated: [StrictQueueRecord]) throws {
        let data = try JSONEncoder().encode(updated)
        defaults.set(data, forKey: Self.key)
        records = updated
    }

    private func put(_ record: StrictQueueRecord) throws {
        try save(records.filter {
            $0.endpoint != record.endpoint || $0.torrentID != record.torrentID
        } + [record])
    }

    private func forget(_ record: StrictQueueRecord) throws {
        try save(records.filter {
            $0.endpoint != record.endpoint || $0.torrentID != record.torrentID
        })
    }

    public func setEnabled(
        _ enabled: Bool,
        torrentID: Int,
        endpoint: String,
        client: any TransmissionRPCProviding
    ) async throws {
        guard !processing, torrentID > 0, !endpoint.isEmpty else {
            throw TransmissionRPCError.invalidTorrentSelection
        }
        processing = true
        defer { processing = false }

        let existing = records.first {
            $0.endpoint == endpoint && $0.torrentID == torrentID
        }
        guard enabled != (existing != nil) else { return }
        if enabled {
            guard let detail = try await client.torrentDetails(id: torrentID) else {
                throw TransmissionRPCError.invalidTorrentSelection
            }
            let record = try StrictQueueRecord(endpoint: endpoint, detail: detail)
            // Persist first: on interrupted operations the daemon may be
            // left with only the current file wanted, never with all files.
            try put(record)
            try await reconcile(record, client: client)
        } else if let existing {
            guard let detail = try await client.torrentDetails(id: torrentID),
                  existing.matches(detail),
                  existing.acceptsObservedWanted(detail) else {
                throw TransmissionRPCError.fileSelectionChanged
            }
            try await client.setQueueFileSelection(
                torrentID: torrentID,
                wanted: existing.orderedSelectedIndices,
                unwanted: existing.originalUnwantedIndices
            )
            guard let confirmed = try await client.torrentDetails(id: torrentID),
                  existing.wantedMatches(confirmed, active: nil) else {
                throw TransmissionRPCError.fileSelectionChanged
            }
            try forget(existing)
        }
    }

    public func advance(
        endpoint: String,
        client: any TransmissionRPCProviding
    ) async throws {
        guard !processing else { return }
        processing = true
        defer { processing = false }
        var firstError: Error?
        for record in records.filter({ $0.endpoint == endpoint }) {
            do {
                try await reconcile(record, client: client)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    private func reconcile(
        _ record: StrictQueueRecord,
        client: any TransmissionRPCProviding
    ) async throws {
        guard let detail = try await client.torrentDetails(id: record.torrentID) else {
            try forget(record)
            return
        }
        guard record.matches(detail) else {
            throw TransmissionRPCError.fileSelectionChanged
        }
        let plan = try record.plan(for: detail)
        if plan.isFinished && record.wantedMatches(detail, active: nil) {
            try forget(record)
            return
        }
        guard record.acceptsObservedWanted(detail) else {
            throw TransmissionRPCError.fileSelectionChanged
        }
        guard let next = plan.activeFileIndex else {
            if !record.wantedMatches(detail, active: nil) {
                try await client.setQueueFileSelection(
                    torrentID: record.torrentID,
                    wanted: record.orderedSelectedIndices,
                    unwanted: record.originalUnwantedIndices
                )
                guard let confirmed = try await client.torrentDetails(
                    id: record.torrentID
                ), record.wantedMatches(confirmed, active: nil) else {
                    throw TransmissionRPCError.fileSelectionChanged
                }
            }
            try forget(record)
            return
        }

        if next == record.activeFileIndex && record.serverSelectionApplied {
            return
        }
        var pending = record
        if next != record.activeFileIndex {
            pending.pendingPreviousFileIndex = record.activeFileIndex
        }
        pending.activeFileIndex = next
        pending.serverSelectionApplied = false
        try put(pending)
        try await client.setQueueFileSelection(
            torrentID: pending.torrentID,
            wanted: [next],
            unwanted: pending.allExceptActive
        )
        guard let confirmed = try await client.torrentDetails(id: pending.torrentID),
              pending.wantedMatches(confirmed, active: next) else {
            throw TransmissionRPCError.fileSelectionChanged
        }
        pending.pendingPreviousFileIndex = nil
        pending.serverSelectionApplied = true
        try put(pending)
    }
}
