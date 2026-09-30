import Foundation

// MARK: - Sprache

/// Deutsch oder Englisch – nach der ersten bevorzugten Systemsprache.
/// Zum Testen überschreibbar: `AGENTBAR_LANG=de|en`.
enum Lang {
    static let isGerman: Bool = {
        if let forced = ProcessInfo.processInfo.environment["AGENTBAR_LANG"]?.lowercased(), !forced.isEmpty {
            return forced.hasPrefix("de")
        }
        return (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("de")
    }()

    /// Locale für Zahlen/Datumsangaben passend zur Sprache.
    static var locale: Locale { Locale(identifier: isGerman ? "de_DE" : "en_US") }
}

/// Liefert den deutschen oder englischen Text.
@inline(__always)
func L(_ de: String, _ en: String) -> String { Lang.isGerman ? de : en }

/// Prozentangabe: deutsch mit schmalem Abstand („80 %“), englisch ohne („80%“).
func percentText(_ v: Int) -> String { L("\(v) %", "\(v)%") }
