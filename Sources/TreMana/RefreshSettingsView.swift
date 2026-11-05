import SwiftUI
import TreManaCore

struct RefreshSettingsView: View {
    @AppStorage(AppearancePreference.key) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(LanguagePreference.storageKey) private var preferredLanguage = LanguagePreference.automatic
    @AppStorage(RefreshPreferenceKeys.enabled) private var autoRefreshEnabled = true
    @AppStorage(RefreshPreferenceKeys.mode) private var refreshMode = RefreshMode.adaptive.rawValue
    @AppStorage(RefreshPreferenceKeys.fixedInterval) private var fixedInterval = 10
    @AppStorage(ToolbarPresentation.storageKey) private var toolbarPresentation = ToolbarPresentation.iconsAndLabels.rawValue

    var body: some View {
        Form {
            Section("Language") {
                Picker("Interface language", selection: $preferredLanguage) {
                    Text("System (automatic)").tag(LanguagePreference.automatic)
                    Text("English").tag("en")
                    Text("Русский").tag("ru")
                }
            }
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("System").tag(AppearanceMode.system.rawValue)
                    Text("Light").tag(AppearanceMode.light.rawValue)
                    Text("Dark").tag(AppearanceMode.dark.rawValue)
                }
            }
            Section("Toolbar") {
                Picker("Toolbar appearance", selection: $toolbarPresentation) {
                    ForEach(ToolbarPresentation.allCases) { option in
                        Text(LocalizedStringKey(option.title)).tag(option.rawValue)
                    }
                }
            }

            Section("Torrent list") {
                Toggle("Automatically refresh torrent information", isOn: $autoRefreshEnabled)

                Picker("Refresh mode", selection: $refreshMode) {
                    Text("Adaptive").tag(RefreshMode.adaptive.rawValue)
                    Text("Fixed").tag(RefreshMode.fixed.rawValue)
                }
                .disabled(!autoRefreshEnabled)

                if refreshMode == RefreshMode.fixed.rawValue {
                    Picker("Update interval", selection: $fixedInterval) {
                        ForEach(RefreshConfiguration.allowedFixedIntervals, id: \.self) { seconds in
                            Text("\(seconds) seconds").tag(seconds)
                        }
                    }
                    .disabled(!autoRefreshEnabled)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 9) {
                    Label("Adaptive · 5 seconds", systemImage: "arrow.down.circle")
                    Text("During downloads and verification.")
                        .foregroundStyle(.secondary)

                    Label("Adaptive · 15 seconds", systemImage: "pause.circle")
                    Text("When connected without active downloads.")
                        .foregroundStyle(.secondary)

                    Label("Background or network errors · 30 seconds", systemImage: "moon")
                    Text("Fixed mode is also limited to 30 seconds while inactive. macOS may suspend background activity.")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(.vertical, 4)
            } header: {
                Text("Refresh behavior")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: 490, height: 505)
        .background { TreManaWindowTint(intensity: 0.72) }
    }
}
