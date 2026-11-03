import Testing
@testable import TreManaCore

@Suite("Interface language selection")
struct LanguagePreferenceTests {
    @Test func systemRussianMatchesRegionalTag() {
        #expect(LanguagePreference.resolve("system", preferredLanguages: ["ru-RU", "en-US"]) == "ru")
        #expect(LanguagePreference.resolve("system", preferredLanguages: ["ru_RU", "en-US"]) == "ru")
    }

    @Test func explicitChoiceOverridesSystemOrder() {
        #expect(LanguagePreference.resolve("en", preferredLanguages: ["ru-RU"]) == "en")
        #expect(LanguagePreference.resolve("ru", preferredLanguages: ["en-US"]) == "ru")
    }

    @Test func unsupportedPreferredLanguagesUseFirstSupportedOrEnglish() {
        #expect(LanguagePreference.resolve("system", preferredLanguages: ["de-DE", "ru-RU"]) == "ru")
        #expect(LanguagePreference.resolve("system", preferredLanguages: ["fr-FR"]) == "en")
        #expect(LanguagePreference.resolve("unexpected", preferredLanguages: ["ru-RU"]) == "ru")
    }

    @Test func emptyPreferencesFallbackToEnglish() {
        #expect(LanguagePreference.resolve("system", preferredLanguages: []) == "en")
    }
}
