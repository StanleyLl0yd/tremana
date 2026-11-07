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

print("SwiftUI model dependencies explicit: PASS")
