import AppKit
import SwiftUI

/// Persists user-resized widths for a native SwiftUI Table without taking over
/// its existing column visibility, ordering, or selection behaviour.
@MainActor
struct TableColumnWidthPersistence: NSViewRepresentable {
    let tableIdentifier: String
    let columnIdentifiers: Set<String>
    let titleIdentifiers: [String: String]

    static let torrentTitleIdentifiers: [String: String] = [
        "Name": "name", "Название": "name",
        "Progress": "progress", "Прогресс": "progress",
        "Status": "status", "Состояние": "status",
        "Download": "download", "Загрузка": "download",
        "Upload": "upload", "Отдача": "upload",
        "Seeds": "seeds", "Сиды": "seeds",
        "Leeches": "leeches", "Личеры": "leeches",
        "ETA": "eta", "Осталось времени": "eta",
        "Ratio": "ratio", "Рейтинг": "ratio",
        "Added": "addedDate", "Добавлен": "addedDate",
        "Total Size": "totalSize", "Общий размер": "totalSize",
        "Downloaded": "downloaded", "Загружено": "downloaded",
        "Uploaded": "uploaded", "Отдано": "uploaded",
        "Remaining": "remaining", "Осталось": "remaining",
        "Connected Peers": "connectedPeers", "Connected peers": "connectedPeers",
        "Подключено пиров": "connectedPeers",
        "Queue": "queuePosition", "Очередь": "queuePosition",
        "Priority": "priority", "Приоритет": "priority"
    ]

    static let fileTitleIdentifiers: [String: String] = [
        "Name": "files.name", "Название": "files.name",
        "Size": "files.size", "Размер": "files.size",
        "Progress": "files.progress", "Прогресс": "files.progress",
        "Download file": "files.download", "Download": "files.download",
        "Скачивать": "files.download",
        "Priority": "files.priority", "Приоритет": "files.priority"
    ]

    func makeNSView(context: Context) -> TableColumnWidthProbeView {
        TableColumnWidthProbeView(
            tableIdentifier: tableIdentifier,
            columnIdentifiers: columnIdentifiers,
            titleIdentifiers: titleIdentifiers
        )
    }

    func updateNSView(_ view: TableColumnWidthProbeView, context: Context) {
        view.configure(
            tableIdentifier: tableIdentifier,
            columnIdentifiers: columnIdentifiers,
            titleIdentifiers: titleIdentifiers
        )
    }
}

@MainActor
final class TableColumnWidthProbeView: NSView {
    private var tableIdentifier: String
    private var columnIdentifiers: Set<String>
    private var titleIdentifiers: [String: String]
    private weak var tableView: NSTableView?
    private var restoredColumnInstances: [String: ObjectIdentifier] = [:]
    private var attachScheduled = false
    private var isRestoring = false

    private var storageKey: String {
        "com.sl.tremana.table-column-widths.v1.\(tableIdentifier)"
    }

    init(
        tableIdentifier: String,
        columnIdentifiers: Set<String>,
        titleIdentifiers: [String: String]
    ) {
        self.tableIdentifier = tableIdentifier
        self.columnIdentifiers = columnIdentifiers
        self.titleIdentifiers = titleIdentifiers
        super.init(frame: .zero)
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleAttach()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleAttach()
    }

    override func layout() {
        super.layout()
        scheduleAttach()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func configure(
        tableIdentifier: String,
        columnIdentifiers: Set<String>,
        titleIdentifiers: [String: String]
    ) {
        guard self.tableIdentifier != tableIdentifier ||
                self.columnIdentifiers != columnIdentifiers ||
                self.titleIdentifiers != titleIdentifiers else { return }
        detach()
        self.tableIdentifier = tableIdentifier
        self.columnIdentifiers = columnIdentifiers
        self.titleIdentifiers = titleIdentifiers
        scheduleAttach()
    }

    private func scheduleAttach() {
        guard !attachScheduled else { return }
        attachScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.attachScheduled = false
            self.attachIfNeeded()
        }
    }

    private func attachIfNeeded() {
        guard let window, let contentView = window.contentView else {
            detach()
            return
        }
        guard let candidate = findTable(in: contentView) else { return }

        if tableView !== candidate {
            detach()
            tableView = candidate
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(columnDidResize(_:)),
                name: NSTableView.columnDidResizeNotification,
                object: candidate
            )
        }
        restoreSavedWidths(in: candidate)
    }

    private func detach() {
        if let tableView {
            NotificationCenter.default.removeObserver(
                self,
                name: NSTableView.columnDidResizeNotification,
                object: tableView
            )
        }
        tableView = nil
        restoredColumnInstances.removeAll()
    }

    private func findTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView, isTarget(table) {
            return table
        }
        for child in view.subviews {
            if let table = findTable(in: child) {
                return table
            }
        }
        return nil
    }

    private func isTarget(_ table: NSTableView) -> Bool {
        let expectedViewID = "\\(tableIdentifier).table"
        if table.identifier.rawValue == expectedViewID ||
            table.accessibilityIdentifier() == expectedViewID {
            return true
        }

        let rawIdentifiers = Set(table.tableColumns.map { $0.identifier.rawValue })
        if rawIdentifiers.intersection(columnIdentifiers).count >= min(2, columnIdentifiers.count) {
            return true
        }

        // SwiftUI may keep its internal NSTableColumn identifiers opaque.
        // Fall back to table-specific header signatures, never generic Name/Progress.
        let titles = Set(table.tableColumns.map { $0.headerCell.stringValue })
        switch tableIdentifier {
        case "torrents":
            return titles.contains("Status") || titles.contains("Состояние") ||
                titles.contains("Upload") || titles.contains("Отдача")
        case "files":
            let hasSize = titles.contains("Size") || titles.contains("Размер")
            let hasDownload = titles.contains("Download file") ||
                titles.contains("Download") || titles.contains("Скачивать")
            let hasPriority = titles.contains("Priority") || titles.contains("Приоритет")
            return hasSize && hasDownload && hasPriority
        default:
            return false
        }
    }

    private func columnIdentifier(_ column: NSTableColumn) -> String? {
        let raw = column.identifier.rawValue
        if columnIdentifiers.contains(raw) { return raw }
        return titleIdentifiers[column.headerCell.stringValue]
    }

    private func restoreSavedWidths(in table: NSTableView) {
        let saved = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: NSNumber] ?? [:]
        isRestoring = true
        defer { isRestoring = false }

        for column in table.tableColumns {
            guard let identifier = columnIdentifier(column) else { continue }
            let instance = ObjectIdentifier(column)
            guard restoredColumnInstances[identifier] != instance else { continue }
            restoredColumnInstances[identifier] = instance

            guard let stored = saved[identifier] else { continue }
            let width = stored.doubleValue
            guard width.isFinite, width > 0 else { continue }
            let minimum = max(1, column.minWidth)
            let maximum = max(minimum, column.maxWidth)
            let restored = min(max(CGFloat(width), minimum), maximum)
            if abs(column.width - restored) > 0.5 {
                column.width = restored
            }
        }
        table.needsLayout = true
    }

    @objc private func columnDidResize(_ notification: Notification) {
        saveWidths()
    }

    private func saveWidths() {
        guard !isRestoring, let tableView else { return }
        var saved = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Double] ?? [:]
        for column in tableView.tableColumns {
            guard let identifier = columnIdentifier(column),
                  column.width.isFinite, column.width > 0 else { continue }
            saved[identifier] = Double(column.width)
        }
        UserDefaults.standard.set(saved, forKey: storageKey)
    }
}
