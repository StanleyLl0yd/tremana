import SwiftUI
import TreManaCore

@main
struct TreManaApp: App {
    @State private var model = TreManaModel()
    @AppStorage(AppearancePreference.key) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(LanguagePreference.storageKey) private var preferredLanguage = LanguagePreference.automatic

    private var preferredAppearance: ColorScheme? {
        (AppearanceMode(rawValue: appearance) ?? .system).scheme
    }

    private var interfaceLocale: Locale {
        Locale(identifier: LanguagePreference.resolve(
            preferredLanguage,
            preferredLanguages: Locale.preferredLanguages
        ))
    }

    var body: some Scene {
        Window("TreMana", id: "main") {
            ContentView(model: model)
                .environment(\.locale, interfaceLocale)
                .preferredColorScheme(preferredAppearance)
                .frame(minWidth: 520, minHeight: 260)
        }
        .defaultSize(width: 1140, height: 740)

        Settings {
            RefreshSettingsView()
                .environment(\.locale, interfaceLocale)
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
