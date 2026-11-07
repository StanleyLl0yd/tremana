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
                        .help("Adaptive refresh: 5 seconds during downloads, 15 when idle, 30 in the background.")
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


            }
            .frame(maxWidth: 490)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                if AdaptiveWindowHeight.shouldUpdate(
                    previous: Double(contentHeight), measured: Double(height)
                ) {
                    contentHeight = height
                }
            }
        }
        .frame(width: 530)
        .scrollIndicators(.automatic)
        .background { TreManaWindowTint(intensity: 0.72) }
        .overlay(alignment: .topLeading) {
            TreManaSettingsWindowSizing(contentHeight: contentHeight)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
