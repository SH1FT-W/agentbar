import Foundation

/// Was der gemeinsame Code (Shared/Sources) über diese App wissen muss.
enum AppConfig: SharedAppConfig {
    /// Sprache zum Testen überschreiben: `AGENTBAR_LANG=de|en`.
    static let langEnvVar = "AGENTBAR_LANG"
}

/// Prozentangabe: deutsch mit schmalem Abstand („80 %“), englisch ohne („80%“).
func percentText(_ v: Int) -> String { L("\(v) %", "\(v)%") }
