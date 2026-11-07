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
    private var localEventMonitor: Any?

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
        installObservers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if tableView?.window !== window {
            detachTable()
        }
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
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
    }

    func configure(
        tableIdentifier: String,
        columnIdentifiers: Set<String>,
        titleIdentifiers: [String: String]
    ) {
        guard self.tableIdentifier != tableIdentifier ||
                self.columnIdentifiers != columnIdentifiers ||
                self.titleIdentifiers != titleIdentifiers else { return }
        detachTable()
        self.tableIdentifier = tableIdentifier
        self.columnIdentifiers = columnIdentifiers
        self.titleIdentifiers = titleIdentifiers
        scheduleAttach()
    }

    private func installObservers() {
        // SwiftUI can insert its native NSTableView after the representable's
        // first layout pass. Retry when the containing window gains subviews.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidUpdate(_:)),
            name: NSWindow.didUpdateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate(_:)),
            name: NSApplication.willTerminateNotification,
            object: nil
        )

        // The resize notification is the primary save path. The local monitor
        // below is a second path for SwiftUI-hosted tables and saves after the
        // mouse-up event has fully completed.
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp]
        ) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.type == .leftMouseDown {
                self.attachIfNeeded()
            } else if event.type == .leftMouseUp {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.attachIfNeeded()
                    self.saveWidths()
                }
            }

            // Do not consume header events. Native NSTableView double-click
            // on a column divider performs its built-in fit-to-cell-content.
            return event
        }
    }

    @objc private func windowDidUpdate(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === self.window else { return }
        guard tableView == nil || tableView?.window !== window ||
                tableView?.tableColumns.isEmpty == true else { return }
        scheduleAttach()
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === tableView?.window else { return }
        saveWidths()
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === tableView?.window else { return }
        saveWidths()
        detachTable()
    }

    @objc private func applicationWillTerminate(_ notification: Notification) {
        saveWidths()
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
            detachTable()
            return
        }
        guard let candidate = findTable(in: contentView) else { return }

        if tableView !== candidate {
            detachTable()
            tableView = candidate
            candidate.allowsColumnResizing = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(columnDidResize(_:)),
                name: NSTableView.columnDidResizeNotification,
                object: candidate
            )
        }
        restoreSavedWidths(in: candidate)
    }

    private func detachTable() {
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
        let expectedViewID = "\(tableIdentifier).table"
        var ancestor: NSView? = table
        while let view = ancestor {
            if view.identifier?.rawValue == expectedViewID ||
                view.accessibilityIdentifier() == expectedViewID {
                return true
            }
            ancestor = view.superview
        }

        let recognized = Set(table.tableColumns.compactMap(columnIdentifier))
            .intersection(columnIdentifiers)
        switch tableIdentifier {
        case "torrents":
            return !recognized.isDisjoint(with: [
                "status", "upload", "ratio", "eta", "totalSize"
            ])
        case "files":
            return !recognized.isDisjoint(with: [
                "files.size", "files.download", "files.priority"
            ])
        default:
            return false
        }
    }

    private func columnIdentifier(_ column: NSTableColumn) -> String? {
        let raw = column.identifier.rawValue
        if columnIdentifiers.contains(raw) { return raw }

        // SwiftUI may expose an opaque AppKit identifier. Try both NSTableColumn
        // title and header-cell title; the latter can differ across OS releases.
        let candidates = [column.title, column.headerCell.stringValue]
        for candidate in candidates {
            let title = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            if let identifier = titleIdentifiers[title] {
                return identifier
            }
            if let match = titleIdentifiers.first(where: {
                $0.key.compare(
                    title,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame
            }) {
                return match.value
            }
        }
        return nil
    }

    private func restoreSavedWidths(in table: NSTableView) {
        let saved = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: NSNumber] ?? [:]
        isRestoring = true
        defer { isRestoring = false }

        for column in table.tableColumns {
            guard let identifier = columnIdentifier(column) else { continue }
            let instance = ObjectIdentifier(column)
            guard restoredColumnInstances[identifier] != instance else { continue }

            if let stored = saved[identifier] {
                let width = stored.doubleValue
                if width.isFinite, width > 0 {
                    let minimum = max(1, column.minWidth)
                    let maximum = max(minimum, column.maxWidth)
                    let restored = min(max(CGFloat(width), minimum), maximum)
                    if abs(column.width - restored) > 0.5 {
                        column.width = restored
                    }
                }
            }
            restoredColumnInstances[identifier] = instance
        }
    }

    @objc private func columnDidResize(_ notification: Notification) {
        saveWidths()
    }

    private func saveWidths() {
        guard !isRestoring, let tableView, tableView.window === window else { return }

        var saved = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: NSNumber] ?? [:]
        var changed = false
        for column in tableView.tableColumns {
            guard let identifier = columnIdentifier(column),
                  column.width.isFinite, column.width > 0 else { continue }
            let width = Double(column.width)
            if let previous = saved[identifier],
               abs(previous.doubleValue - width) < 0.5 {
                continue
            }
            saved[identifier] = NSNumber(value: width)
            changed = true
        }
        if changed {
            UserDefaults.standard.set(saved, forKey: storageKey)
        }
    }
}
