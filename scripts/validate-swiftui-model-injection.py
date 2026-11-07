#!/usr/bin/env python3
"""Prevent a SwiftUI runtime trap caused by missing observable model environment.

The UI passes the observable model explicitly, including to SwiftUI Table cells,
context menus, and sheets, which may be hosted in separate view hierarchies.
This check is deliberately lightweight; macOS CI must also compile the app.
"""

from pathlib import Path

root = Path(__file__).resolve().parents[1]
ui = root / "Sources" / "TreMana"

source_files = sorted(ui.rglob("*.swift"))
assert source_files, "UI Swift sources not found"

disallowed = []
for path in source_files:
    source = path.read_text(encoding="utf-8")
    if "@Environment(TreManaModel.self)" in source:
        disallowed.append(str(path.relative_to(root)))

assert not disallowed, "UI must explicitly receive TreManaModel: " + ", ".join(disallowed)

model = (root / "Sources" / "TreManaCore" / "TreManaModel.swift").read_text(encoding="utf-8")
model_class = model.index("public final class TreManaModel")
for method in ["setFileWanted", "setFilePriority", "applyFileBatch"]:
    start = model.index("public func " + method + "(", model_class)
    end = model.find("\n    public func ", start + 1)
    assert end >= 0, "Unable to locate end of " + method
    assert "selectedTorrentDetail = nil" not in model[start:end], (
        method + " must keep the existing inspector snapshot mounted during RPC verification"
    )

app = (ui / "TreManaApp.swift").read_text(encoding="utf-8")
assert "ContentView(model: model)" in app, "Root must explicitly inject the live model"
assert ".environment(model)" not in app, "Do not depend on model environment lookup"

content = (ui / "ContentView.swift").read_text(encoding="utf-8")
inspector = (ui / "TorrentInspectorView.swift").read_text(encoding="utf-8")

# These are the most fragile detached SwiftUI hosting contexts.
for call in [
    "AddTorrentSheet(model: model)",
    "RemoteTorrentActionSheet(model: model, request: request)",
    "TorrentInspectorView(model: model, selectedTab: selectedInspectorTab)",
]:
    assert call in content, "Missing explicit model at view boundary: " + call

for call in [
    "FileWantedCell(model: model,",
    "FilePriorityCell(model: model,",
    "FileBatchActions(\n                            model: model,",
]:
    assert call in inspector, "Missing explicit model for detached Table UI: " + call

# File and folder selection must share one deterministic custom control. Using
# Toggle(.checkbox) beside a separately drawn folder button causes size/color
# divergence, especially when the app window is inactive.
assert "private struct FileWantedControl: View" in inspector
assert inspector.count("FileWantedControl(") == 2, "Files and folders must use the same wanted control"
assert ".toggleStyle(.checkbox)" not in inspector, "Do not mix native and custom file-selection controls"
assert "checkmark.square.fill" not in inspector, "Folder selection must use the shared control"
assert '"folder.wanted.\\(node.id)"' in inspector
assert '"file.wanted.\\(row.id)"' in inspector

for cell in [
    "FileWantedCell", "FilePriorityCell",
    "FileTreeWantedCell", "FileTreePriorityCell",
]:
    assert f"private struct {cell}: View, @MainActor Equatable" in inspector, (
        cell + " must compare only the values that affect its own cell"
    )
assert inspector.count(".equatable()") == 4, "All four file/folder cells must be diff-isolated"
assert ".allowsHitTesting(!model.isBusy)" in inspector, (
    "Block interaction during RPC without applying disabled styling to every cell"
)
widths = (ui / "TableColumnWidthPersistence.swift").read_text(encoding="utf-8")
assert "NSTableView.columnDidResizeNotification" in widths
assert "NSEvent.addLocalMonitorForEvents" in widths
assert "NSWindow.didUpdateNotification" in widths
assert "windowDidResignKey" in widths
assert "applicationWillTerminate" in widths
assert "column.title" in widths and "headerCell.stringValue" in widths
assert "UserDefaults.standard.set" in widths
assert "return event" in widths, "Column header events must reach native AppKit fit-to-content handling"
assert "fit-to-cell-content" in widths
assert "TableColumnWidthPersistence(" in content
assert "TableColumnWidthPersistence(" in inspector
assert '.customizationID("files.name")' in inspector
assert '.customizationID("files.priority")' in inspector

for cell, next_cell in [
    ("FileWantedCell", "FilePriorityCell"),
    ("FilePriorityCell", "FileBatchActions"),
]:
    start = inspector.index("private struct " + cell)
    end = inspector.index("private struct " + next_cell, start + 1)
    assert "model.selectedTorrentDetail" not in inspector[start:end], (
        cell + " must consume its immutable row snapshot, not observe the whole torrent detail"
    )
    assert "isEnabled: !model.isBusy" not in inspector[start:end]
    assert ".disabled(model.isBusy)" not in inspector[start:end]

print("SwiftUI model dependencies explicit: PASS")
print("File mutations preserve the inspector snapshot: PASS")
print("File/folder cell updates are isolated: PASS")
print("Column-width probes retry attachment and save after mouse-up: PASS")
print("Native AppKit double-click fit-to-content remains enabled: PASS")
