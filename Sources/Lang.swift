import Foundation

// MARK: - App configuration

/// What the shared sources need to know about the app that compiles them. The app declares
/// `enum AppConfig: SharedAppConfig { ... }` in its own Sources (see tools/AppConfig.swift);
/// the shared code refers to `AppConfig` by name, which works because everything is compiled
/// into one module.
protocol SharedAppConfig {
    /// Environment variable that forces the UI language for tests and screenshots (`de` or `en`),
    /// for example `AGENTBAR_LANG`.
    static var langEnvVar: String { get }
}

// MARK: - Language

/// German or English, following the first preferred system language.
/// Overridable for tests and screenshots through the variable named by `AppConfig.langEnvVar`.
enum Lang {
    static let isGerman: Bool = {
        if let forced = ProcessInfo.processInfo.environment[AppConfig.langEnvVar]?.lowercased(), !forced.isEmpty {
            return forced.hasPrefix("de")
        }
        return (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("de")
    }()

    /// Locale for numbers and dates matching the language.
    static var locale: Locale { Locale(identifier: isGerman ? "de_DE" : "en_US") }
}

/// Returns the German or the English text.
@inline(__always)
func L(_ de: String, _ en: String) -> String { Lang.isGerman ? de : en }
