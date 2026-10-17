// Template: copy to <app>/Sources/AppConfig.swift and fill in the values.
// The shared sources (Shared/Sources) refer to `AppConfig` by name.
enum AppConfig: SharedAppConfig {
    /// Environment variable that forces the UI language (`de` or `en`) for tests and screenshots.
    static let langEnvVar = "MYAPP_LANG"
}
