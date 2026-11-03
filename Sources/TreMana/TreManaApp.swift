import SwiftUI
import TreManaCore

@main
struct TreManaApp: App {
    @State private var model = TreManaModel()
    @AppStorage(AppearancePreference.key) private var appearance = AppearanceMode.system.rawValue

    private var preferredAppearance: ColorScheme? {
        (AppearanceMode(rawValue: appearance) ?? .system).scheme
    }

    var body: some Scene {
        Window("TreMana", id: "main") {
            ContentView()
                .environment(model)
                .preferredColorScheme(preferredAppearance)
                .frame(minWidth: 840, minHeight: 560)
        }
        .defaultSize(width: 1140, height: 740)

        Settings {
            RefreshSettingsView()
                .preferredColorScheme(preferredAppearance)
        }
        .commands {
            CommandMenu("Torrents") {
                Button("Refresh Torrent List") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!model.isConnected || model.isBusy || model.isRefreshing)
            }
        }
    }
}
