import Foundation

/// Only declare supported languages with complete, tested translations.
public enum LanguagePreference {
    public static let storageKey = "com.sl.tremana.interface-language"
    public static let automatic = "system"
    public static let supportedCodes: [String] = ["en", "ru"]

    /// Resolve the user's ordered macOS language list, including regional tags.
    public static func resolve(_ stored: String, preferredLanguages: [String]) -> String {
        if stored != automatic, supportedCodes.contains(stored) {
            return stored
        }
        for preferred in preferredLanguages {
            let normalized = preferred.replacingOccurrences(of: "_", with: "-")
            let baseLanguage = normalized.split(separator: "-").first.map(String.init)
            if let baseLanguage,
               supportedCodes.contains(baseLanguage.lowercased()) {
                return baseLanguage.lowercased()
            }
        }
        return "en"
    }
}
