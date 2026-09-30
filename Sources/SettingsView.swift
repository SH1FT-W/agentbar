import SwiftUI

enum SettingsWindow {
    private static var window: NSWindow?

    @MainActor static func show(_ store: AppStore) {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView().environmentObject(store))
            let w = NSWindow(contentViewController: host)
            w.title = L("AgentBar-Einstellungen", "AgentBar Settings")
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
    @AppStorage(Prefs.notifyUpdate) private var notifyUpdate = true
    @AppStorage(Prefs.quotaThreshold) private var threshold = 80.0
    @AppStorage(Prefs.notifyWhenFrontmost) private var whenFront = false
    @AppStorage(Prefs.showCount) private var showCount = true
    @AppStorage(Prefs.showQuota) private var showQuota = false
    @AppStorage(Prefs.visibleHours) private var hours = 2.0
    @AppStorage(Prefs.officeFloating) private var floating = true
    @AppStorage(Prefs.officeOpacity) private var opacity = 1.0
    @AppStorage(Prefs.officeDaylight) private var daylight = true
    @AppStorage(Prefs.quotaEnabled) private var quotaEnabled = true
    @AppStorage(Prefs.peersEnabled) private var peersEnabled = false
    @AppStorage(Prefs.peerCode) private var peerCode = ""
    @State private var codeInput = ""
    @State private var codeInvalid = false
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
                        Text(L("Deine Claude-Agenten im Blick – direkt in der Menüleiste.", "Keep an eye on your Claude agents – right in the menu bar."))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(L("Mitteilungen", "Notifications")) {
                Toggle(isOn: $notifyWaiting) { SettingLabel(L("Wenn ein Agent dich braucht", "When an agent needs you"), "hand.raised.fill", .orange) }
                Toggle(isOn: $notifyDone) { SettingLabel(L("Wenn ein Agent fertig ist", "When an agent is done"), "checkmark", .green) }
                Toggle(isOn: $notifyError) { SettingLabel(L("Bei Fehlern", "On errors"), "exclamationmark", .red) }
                Toggle(isOn: $notifyQuota) { SettingLabel(L("Kontingent wird knapp", "Usage running low"), "gauge.with.needle.fill", .pink) }
                if notifyQuota {
                    LabeledContent {
                        HStack(spacing: 10) {
                            Slider(value: $threshold, in: 50...95, step: 5).frame(width: 150)
                            Text(percentText(Int(threshold))).monospacedDigit().foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    } label: {
                        SettingLabel(L("Warnen ab", "Warn at"), nil, .clear)
                    }
                }
                Toggle(isOn: $notifyUpdate) { SettingLabel(L("Neue AgentBar-Version", "New AgentBar version"), "arrow.down.app.fill", .blue) }
                Toggle(isOn: $whenFront) {
                    SettingLabel(L("Auch im Vordergrund", "Even when in front"), "macwindow", .gray,
                                 note: L("Auch melden, wenn die Sitzung gerade sichtbar ist.", "Also notify when the session is visible."))
                }
            }

            Section(L("Menüleiste", "Menu Bar")) {
                Toggle(isOn: $showCount) { SettingLabel(L("Anzahl aktiver Agenten", "Number of active agents"), "number", .blue) }
                Toggle(isOn: $showQuota) { SettingLabel(L("5-Stunden-Kontingent in %", "5-hour usage in %"), "percent", .blue) }
            }

            Section {
                Picker(selection: $hours) {
                    Text(L("30 Minuten", "30 minutes")).tag(0.5)
                    Text(L("2 Stunden", "2 hours")).tag(2.0)
                    Text(L("8 Stunden", "8 hours")).tag(8.0)
                    Text(L("24 Stunden", "24 hours")).tag(24.0)
                } label: {
                    SettingLabel(L("Ruhende Sitzungen zeigen", "Show idle sessions for"), "clock", .indigo)
                }
                .onChange(of: hours) { _ in store.monitor.rescan() }
                Toggle(isOn: $quotaEnabled) {
                    SettingLabel(L("Kontingent abrufen", "Fetch usage"), "chart.pie.fill", .pink,
                                 note: L("Liest dein Nutzungs-Kontingent bei Anthropic.", "Reads your usage limits from Anthropic."))
                }
                LabeledContent {
                    Button(store.hooksInstalled ? L("Entfernen", "Remove") : L("Einrichten", "Set Up")) { store.setHooks(!store.hooksInstalled) }
                } label: {
                    SettingLabel(L("Präzise Erkennung", "Precise detection"), "scope", .accentColor,
                                 note: store.hooksInstalled ? L("Aktiv – Claude Code meldet sich über Hooks.", "On – Claude Code reports via hooks.")
                                                             : L("Aus – AgentBar schätzt den Status.", "Off – AgentBar estimates the status."))
                }
            } header: {
                Text(L("Sitzungen", "Sessions"))
            } footer: {
                Text(L("Die Hooks stehen in ~/.claude/settings.json (Sicherung liegt daneben) und schreiben nur eine Zeile nach ~/Library/Application Support/AgentBar/hooks.log – kein Netzwerk.", "The hooks live in ~/.claude/settings.json (a backup sits next to it) and only write one line to ~/Library/Application Support/AgentBar/hooks.log – no network."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Toggle(isOn: $peersEnabled) {
                    SettingLabel(L("Andere Macs zeigen", "Show other Macs"), "laptopcomputer", .teal,
                                 note: L("Sitzungen deiner anderen Macs im selben Netzwerk.", "Sessions from your other Macs on the same network."))
                }
                .onChange(of: peersEnabled) { on in
                    if on, PeerCode.normalize(peerCode) == nil { peerCode = PeerCode.generate() }
                    store.peers.configure()
                }
                if peersEnabled {
                    LabeledContent {
                        HStack(spacing: 8) {
                            Text(peerCode).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(peerCode, forType: .string) } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .help(L("Kopieren", "Copy"))
                            Button { peerCode = PeerCode.generate(); store.peers.configure() } label: { Image(systemName: "arrow.clockwise") }
                                .help(L("Neuen Code erzeugen – alle anderen Macs brauchen ihn dann auch", "New code – all other Macs need it too"))
                        }
                        .buttonStyle(.borderless)
                    } label: {
                        SettingLabel(L("Kopplungscode", "Pairing code"), "key.fill", .gray)
                    }
                    LabeledContent {
                        HStack(spacing: 8) {
                            TextField("", text: $codeInput, prompt: Text("XXXX-XXXX-XXXX")).labelsHidden()
                                .textFieldStyle(.roundedBorder).frame(width: 150)
                                .font(.system(size: 12, design: .monospaced))
                                .onSubmit(applyCode)
                            Button(L("Übernehmen", "Use"), action: applyCode).disabled(codeInput.isEmpty)
                        }
                    } label: {
                        SettingLabel(L("Code eines anderen Macs", "Code from another Mac"), "keyboard", .gray,
                                     note: codeInvalid ? L("Ungültiger Code – 12 Zeichen, z. B. ABCD-EFGH-JKLM.", "Invalid code – 12 characters, e.g. ABCD-EFGH-JKLM.") : nil)
                    }
                    LabeledContent {
                        PeerStatus(hub: store.peers)
                    } label: {
                        SettingLabel(L("Verbunden", "Connected"), "wifi", .green)
                    }
                }
            } header: {
                Text(L("Andere Macs", "Other Macs"))
            } footer: {
                Text(L("Auf allen Macs denselben Code verwenden. Die Verbindung bleibt im lokalen Netzwerk und ist mit dem Code verschlüsselt. Übertragen werden nur Status, Projekt, Titel und Tätigkeit der Sitzungen.",
                       "Use the same code on all your Macs. The connection stays on your local network and is encrypted with the code. Only the status, project, title and activity of sessions are shared."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(L("Büro", "Office")) {
                Toggle(isOn: $floating) { SettingLabel(L("Immer im Vordergrund", "Always on top"), "pin.fill", .orange) }
                    .onChange(of: floating) { _ in store.office.applyPrefs() }
                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(value: $opacity, in: 0.4...1).frame(width: 150)
                            .onChange(of: opacity) { _ in store.office.applyPrefs() }
                        Text(percentText(Int((opacity * 100).rounded()))).monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                } label: {
                    SettingLabel(L("Deckkraft", "Opacity"), "circle.lefthalf.filled", .gray)
                }
                Toggle(isOn: $daylight) { SettingLabel(L("Himmel folgt der Tageszeit", "Sky follows time of day"), "sun.horizon.fill", .cyan) }
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

extension SettingsView {
    private func applyCode() {
        guard let c = PeerCode.normalize(codeInput) else { codeInvalid = true; return }
        codeInvalid = false
        codeInput = ""
        peerCode = c
        store.peers.configure()
    }
}

/// Wer gerade verbunden ist (beobachtet den PeerHub direkt, damit die Zeile live bleibt).
private struct PeerStatus: View {
    @ObservedObject var hub: PeerHub

    var body: some View {
        let names = hub.peers.values.map(\.name).sorted()
        Text(hub.problem ?? (names.isEmpty ? L("Suche andere Macs …", "Looking for other Macs …") : names.joined(separator: ", ")))
            .foregroundStyle(hub.problem == nil ? Color.secondary : Color.orange).multilineTextAlignment(.trailing)
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
