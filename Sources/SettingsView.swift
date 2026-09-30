import SwiftUI

enum SettingsWindow {
    private static var window: NSWindow?

    @MainActor static func show(_ store: AppStore) {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView().environmentObject(store))
            let w = NSWindow(contentViewController: host)
            w.title = "AgentBar-Einstellungen"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Aufbau wie die Systemeinstellungen in macOS 26/27: Kopf mit App-Symbol, darunter gruppierte Abschnitte,
/// jede Zeile mit farbigem Symbol-Plättchen.
struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage(Prefs.notifyWaiting) private var notifyWaiting = true
    @AppStorage(Prefs.notifyDone) private var notifyDone = true
    @AppStorage(Prefs.notifyError) private var notifyError = true
    @AppStorage(Prefs.notifyQuota) private var notifyQuota = true
    @AppStorage(Prefs.quotaThreshold) private var threshold = 80.0
    @AppStorage(Prefs.notifyWhenFrontmost) private var whenFront = false
    @AppStorage(Prefs.showCount) private var showCount = true
    @AppStorage(Prefs.showQuota) private var showQuota = false
    @AppStorage(Prefs.visibleHours) private var hours = 2.0
    @AppStorage(Prefs.officeFloating) private var floating = true
    @AppStorage(Prefs.officeOpacity) private var opacity = 1.0
    @AppStorage(Prefs.officeDaylight) private var daylight = true
    @AppStorage(Prefs.quotaEnabled) private var quotaEnabled = true
    var height: CGFloat = 700

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    // Eigenes Plättchen statt App-Symbol (AgentBar hat keins) – wie die Kopf-Symbole der Systemeinstellungen
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.gradient)
                        Image(systemName: "sparkles").font(.system(size: 24, weight: .medium)).foregroundStyle(.white)
                    }
                    .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AgentBar").font(.system(size: 15, weight: .semibold))
                        Text("Deine Claude-Agenten im Blick – direkt in der Menüleiste.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Mitteilungen") {
                Toggle(isOn: $notifyWaiting) { SettingLabel("Wenn ein Agent dich braucht", "hand.raised.fill", .orange) }
                Toggle(isOn: $notifyDone) { SettingLabel("Wenn ein Agent fertig ist", "checkmark", .green) }
                Toggle(isOn: $notifyError) { SettingLabel("Bei Fehlern", "exclamationmark", .red) }
                Toggle(isOn: $notifyQuota) { SettingLabel("Kontingent wird knapp", "gauge.with.needle.fill", .pink) }
                if notifyQuota {
                    LabeledContent {
                        HStack(spacing: 10) {
                            Slider(value: $threshold, in: 50...95, step: 5).frame(width: 150)
                            Text("\(Int(threshold)) %").monospacedDigit().foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    } label: {
                        SettingLabel("Warnen ab", nil, .clear)
                    }
                }
                Toggle(isOn: $whenFront) {
                    SettingLabel("Auch im Vordergrund", "macwindow", .gray,
                                 note: "Auch melden, wenn die Sitzung gerade sichtbar ist.")
                }
            }

            Section("Menüleiste") {
                Toggle(isOn: $showCount) { SettingLabel("Anzahl aktiver Agenten", "number", .blue) }
                Toggle(isOn: $showQuota) { SettingLabel("5-Stunden-Kontingent in %", "percent", .blue) }
            }

            Section {
                Picker(selection: $hours) {
                    Text("30 Minuten").tag(0.5)
                    Text("2 Stunden").tag(2.0)
                    Text("8 Stunden").tag(8.0)
                    Text("24 Stunden").tag(24.0)
                } label: {
                    SettingLabel("Ruhende Sitzungen zeigen", "clock", .indigo)
                }
                .onChange(of: hours) { _ in store.monitor.rescan() }
                Toggle(isOn: $quotaEnabled) {
                    SettingLabel("Kontingent abrufen", "chart.pie.fill", .pink,
                                 note: "Liest dein Nutzungs-Kontingent bei Anthropic.")
                }
                LabeledContent {
                    Button(store.hooksInstalled ? "Entfernen" : "Einrichten") { store.setHooks(!store.hooksInstalled) }
                } label: {
                    SettingLabel("Präzise Erkennung", "scope", .accentColor,
                                 note: store.hooksInstalled ? "Aktiv – Claude Code meldet sich über Hooks." : "Aus – AgentBar schätzt den Status.")
                }
            } header: {
                Text("Sitzungen")
            } footer: {
                Text("Die Hooks stehen in ~/.claude/settings.json (Sicherung liegt daneben) und schreiben nur eine Zeile nach ~/Library/Application Support/AgentBar/hooks.log – kein Netzwerk.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Büro") {
                Toggle(isOn: $floating) { SettingLabel("Immer im Vordergrund", "pin.fill", .orange) }
                    .onChange(of: floating) { _ in store.office.applyPrefs() }
                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(value: $opacity, in: 0.4...1).frame(width: 150)
                            .onChange(of: opacity) { _ in store.office.applyPrefs() }
                        Text("\(Int((opacity * 100).rounded())) %").monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                } label: {
                    SettingLabel("Deckkraft", "circle.lefthalf.filled", .gray)
                }
                Toggle(isOn: $daylight) { SettingLabel("Himmel folgt der Tageszeit", "sun.horizon.fill", .cyan) }
            }

            Section {
                LabeledContent {
                    Text(AppInfo.version).foregroundStyle(.secondary).monospacedDigit()
                } label: {
                    SettingLabel("Version", "info", .gray)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: height)
    }
}

/// Zeilen-Beschriftung wie in den Systemeinstellungen: farbiges Plättchen mit weißem Symbol, Titel, optional Erklärung.
struct SettingLabel: View {
    let title: String
    let icon: String?
    let tint: Color
    var note: String? = nil

    init(_ title: String, _ icon: String?, _ tint: Color, note: String? = nil) {
        self.title = title; self.icon = icon; self.tint = tint; self.note = note
    }

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                if let icon {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.gradient)
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let note { Text(note).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
        }
    }
}
