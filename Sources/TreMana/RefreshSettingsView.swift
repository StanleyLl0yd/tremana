import SwiftUI
import TreManaCore

struct RefreshSettingsView: View {
    @AppStorage(AppearancePreference.key) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(LanguagePreference.storageKey) private var preferredLanguage = LanguagePreference.automatic
    @AppStorage(RefreshPreferenceKeys.enabled) private var autoRefreshEnabled = true
    @AppStorage(RefreshPreferenceKeys.mode) private var refreshMode = RefreshMode.adaptive.rawValue
    @AppStorage(RefreshPreferenceKeys.fixedInterval) private var fixedInterval = 10
    @AppStorage(ToolbarPresentation.storageKey) private var toolbarPresentation = ToolbarPresentation.iconsAndLabels.rawValue
    @State private var contentHeight: CGFloat = 540

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                CompactFormSection("Language") {
                    CompactFormRow("Interface language") {
                        Picker("Interface language", selection: $preferredLanguage) {
                            Text("System (automatic)").tag(LanguagePreference.automatic)
                            Text("English").tag("en")
                            Text("Русский").tag("ru")
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }

                CompactFormSection("Appearance") {
                    CompactFormRow("Theme") {
                        Picker("Theme", selection: $appearance) {
                            Text("System").tag(AppearanceMode.system.rawValue)
                            Text("Light").tag(AppearanceMode.light.rawValue)
                            Text("Dark").tag(AppearanceMode.dark.rawValue)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }

                CompactFormSection("Toolbar") {
                    CompactFormRow("Toolbar appearance") {
                        Picker("Toolbar appearance", selection: $toolbarPresentation) {
                            ForEach(ToolbarPresentation.allCases) { option in
                                Text(LocalizedStringKey(option.title)).tag(option.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }

                CompactFormSection("Torrent list") {
                    CompactFormRow("Automatically refresh torrent information") {
                        Toggle(
                            "Automatically refresh torrent information",
                            isOn: $autoRefreshEnabled
                        )
                        .labelsHidden()
                    }
                    Divider().padding(.leading, 13)
                    CompactFormRow("Refresh mode") {
                        Picker("Refresh mode", selection: $refreshMode) {
                            Text("Adaptive").tag(RefreshMode.adaptive.rawValue)
                            Text("Fixed").tag(RefreshMode.fixed.rawValue)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .disabled(!autoRefreshEnabled)
                    }

                    if refreshMode == RefreshMode.fixed.rawValue {
                        Divider().padding(.leading, 13)
                        CompactFormRow("Update interval") {
                            Picker("Update interval", selection: $fixedInterval) {
                                ForEach(RefreshConfiguration.allowedFixedIntervals, id: \.self) { seconds in
                                    Text("\(seconds) seconds").tag(seconds)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .disabled(!autoRefreshEnabled)
                        }
                    }
                }

                CompactFormSection("Refresh behavior") {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Adaptive · 5 seconds", systemImage: "arrow.down.circle")
                        Text("During downloads and verification.")
                            .foregroundStyle(.secondary)

                        Divider()
                        Label("Adaptive · 15 seconds", systemImage: "pause.circle")
                        Text("When connected without active downloads.")
                            .foregroundStyle(.secondary)

                        Divider()
                        Label("Background or network errors · 30 seconds", systemImage: "moon")
                        Text("Fixed mode is also limited to 30 seconds while inactive. macOS may suspend background activity.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
                }
            }
            .frame(maxWidth: 530)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .reportNaturalHeight()
        }
        .frame(width: 570)
        .scrollIndicators(.automatic)
        .background { TreManaWindowTint(intensity: 0.72) }
        .background {
            TreManaSettingsWindowSizing(contentHeight: contentHeight)
                .frame(width: 0, height: 0)
        }
        .onPreferenceChange(MeasuredContentHeight.self) { height in
            if height > 0 && abs(height - contentHeight) > 1 {
                contentHeight = height
            }
        }
    }
}
