import SwiftUI
import UserNotifications

enum SettingsWindow {
    private static var window: NSWindow?

    @MainActor static func show(_ store: AppStore) {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView().environmentObject(store))
            // Nur Mindestgröße vom Inhalt – die Höhe ist frei veränderbar, das Formular scrollt
            host.sizingOptions = [.minSize]
            let w = NSWindow(contentViewController: host)
            w.title = L("AgentBar-Einstellungen", "AgentBar Settings")
            w.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            w.setContentSize(NSSize(width: 500, height: 680))
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

/// Aufbau wie die Systemeinstellungen in macOS 26/27: kompakter Kopf, darunter gruppierte Abschnitte,
/// jede Zeile mit farbigem Symbol-Plättchen. Das Fenster ist in der Höhe veränderbar, das Formular scrollt.
struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage(Prefs.notifyWaiting) private var notifyWaiting = true
    @AppStorage(Prefs.notifyDone) private var notifyDone = true
    @AppStorage(Prefs.notifyError) private var notifyError = true
    @AppStorage(Prefs.notifyQuota) private var notifyQuota = true
    @AppStorage(Prefs.notifyUpdate) private var notifyUpdate = true
    @AppStorage(Prefs.notifyContext) private var notifyContext = true
    @AppStorage(Prefs.notifyStalled) private var notifyStalled = false
    @AppStorage(Prefs.quietHours) private var quietHours = false
    @AppStorage(Prefs.quietFrom) private var quietFrom = 22
    @AppStorage(Prefs.quietTo) private var quietTo = 7
    @AppStorage(Prefs.notifyPeers) private var notifyPeers = false
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
    @AppStorage(Prefs.keepAwake) private var keepAwake = KeepAwakeMode.off.rawValue
    @State private var codeInput = ""
    @State private var codeInvalid = false
    @State private var notificationsDenied = false
    @State private var copied = false
    /// Feste Höhe nur für Snapshots (ganzes Formular auf einem Bild); nil = Fenster bestimmt die Höhe.
    var height: CGFloat? = nil

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    // Eigenes Plättchen statt App-Symbol – wie die Kopf-Symbole der Systemeinstellungen
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.gradient)
                        Image(systemName: "sparkles").font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                    }
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("AgentBar").font(.system(size: 13, weight: .semibold))
                        Text(L("Deine Claude-Agenten im Blick – direkt in der Menüleiste.", "Keep an eye on your Claude agents – right in the menu bar."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }

            Section(L("Allgemein", "General")) {
                Toggle(isOn: Binding(get: { store.loginItemEnabled }, set: { store.setLoginItem($0) })) {
                    SettingLabel(L("Beim Anmelden starten", "Launch at login"), "power", .gray)
                }
                Picker(selection: $keepAwake) {
                    ForEach(KeepAwakeMode.allCases) { Text($0.label).tag($0.rawValue) }
                } label: {
                    SettingLabel(L("Wach bleiben", "Keep awake"), "cup.and.saucer.fill", .brown,
                                 note: L("Verhindert den Ruhezustand des Macs.", "Keeps your Mac from sleeping."))
                }
                .onChange(of: keepAwake) { store.updateKeepAwake() }
                LabeledContent {
                    if let problem = store.hotKeyProblem {
                        Text(problem).font(.caption).foregroundStyle(.orange).lineLimit(2).multilineTextAlignment(.trailing)
                    }
                    KeyCap(text: "⌃⌥A")
                } label: {
                    SettingLabel(L("Büro ein- und ausblenden", "Show or hide Office"), "keyboard", .gray)
                }
            }

            Section(L("Mitteilungen", "Notifications")) {
                if notificationsDenied {
                    LabeledContent {
                        Button(L("Öffnen …", "Open…")) { openSettings("com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")") }
                    } label: {
                        SettingLabel(L("In macOS ausgeschaltet", "Turned off in macOS"), "bell.slash.fill", .orange,
                                     note: L("AgentBar darf keine Mitteilungen zeigen – in den Systemeinstellungen erlauben.", "AgentBar isn’t allowed to show notifications – allow it in System Settings."))
                    }
                }
                Toggle(isOn: $notifyWaiting) { SettingLabel(L("Wenn ein Agent dich braucht", "When an agent needs you"), "hand.raised.fill", .orange) }
                Toggle(isOn: $notifyDone) { SettingLabel(L("Wenn ein Agent fertig ist", "When an agent is done"), "checkmark", .green) }
                Toggle(isOn: $notifyError) { SettingLabel(L("Bei Fehlern", "On errors"), "exclamationmark", .red) }
                Toggle(isOn: $notifyContext) {
                    SettingLabel(L("Kontext fast voll", "Context almost full"), "text.line.last.and.arrowtriangle.forward", .orange,
                                 note: L("Ab 85 % des Kontextfensters.", "At 85% of the context window."))
                }
                Toggle(isOn: $notifyStalled) {
                    SettingLabel(L("Agent hängt vielleicht", "Agent may be stuck"), "hourglass", .yellow,
                                 note: L("Arbeitet seit 10 Minuten ohne neues Lebenszeichen.", "Working for 10 minutes without any new activity."))
                }
                Toggle(isOn: $notifyQuota) { SettingLabel(L("Kontingent wird knapp", "Usage running low"), "gauge.with.needle.fill", .pink) }
                    .disabled(!quotaEnabled)
                if notifyQuota, quotaEnabled {
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
                Toggle(isOn: $quietHours) {
                    SettingLabel(L("Ruhezeiten", "Quiet hours"), "moon.fill", .indigo,
                                 note: L("In dieser Zeit keine Mitteilungen.", "No notifications during this time."))
                }
                if quietHours {
                    LabeledContent {
                        HStack(spacing: 6) {
                            hourPicker($quietFrom)
                            Text(L("bis", "to")).foregroundStyle(.secondary)
                            hourPicker($quietTo)
                        }
                    } label: {
                        SettingLabel(L("Von", "From"), nil, .clear)
                    }
                }
            }

            Section(L("Menüleiste", "Menu Bar")) {
                Toggle(isOn: $showCount) { SettingLabel(L("Anzahl aktiver Agenten", "Number of active agents"), "number", .blue) }
            }

            Section(L("Kontingent", "Usage")) {
                Toggle(isOn: $quotaEnabled) {
                    SettingLabel(L("Kontingent abrufen", "Fetch usage"), "chart.pie.fill", .pink,
                                 note: L("Liest dein Nutzungs-Kontingent bei Anthropic.", "Reads your usage limits from Anthropic."))
                }
                .onChange(of: quotaEnabled) { _, on in if on { Task { await store.quota.refresh() } } }
                Toggle(isOn: $showQuota) { SettingLabel(L("5-Stunden-Kontingent in der Menüleiste", "5-hour usage in the menu bar"), "percent", .blue) }
                    .disabled(!quotaEnabled)
            }

            Section {
                Picker(selection: $hours) {
                    Text(L("30 Minuten", "30 minutes")).tag(0.5)
                    Text(L("2 Stunden", "2 hours")).tag(2.0)
                    Text(L("8 Stunden", "8 hours")).tag(8.0)
                    Text(L("24 Stunden", "24 hours")).tag(24.0)
                } label: {
                    SettingLabel(L("Ruhende Sitzungen zeigen für", "Show idle sessions for"), "clock", .indigo)
                }
                .onChange(of: hours) { store.monitor.rescan() }
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
                .onChange(of: peersEnabled) { _, on in
                    if on, PeerCode.normalize(peerCode) == nil { peerCode = PeerCode.generate() }
                    store.peers.configure()
                }
                if peersEnabled {
                    Toggle(isOn: $notifyPeers) {
                        SettingLabel(L("Mitteilungen anderer Macs", "Notifications from other Macs"), "bell.badge.fill", .red,
                                     note: L("Auch melden, wenn dort ein Agent dich braucht oder fertig ist.", "Also notify when an agent there needs you or is done."))
                    }
                    LabeledContent {
                        HStack(spacing: 8) {
                            Text(peerCode).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            Button { copy(peerCode) } label: { Image(systemName: "doc.on.doc") }
                                .help(L("Kopieren", "Copy")).accessibilityLabel(L("Kopieren", "Copy"))
                            Button { peerCode = PeerCode.generate(); store.peers.configure() } label: { Image(systemName: "arrow.clockwise") }
                                .help(L("Neuen Code erzeugen – alle anderen Macs brauchen ihn dann auch", "New code – all other Macs need it too"))
                                .accessibilityLabel(L("Neuen Code erzeugen", "New code"))
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
                        SettingLabel(L("Code eingeben", "Enter code"), "keyboard", .gray,
                                     note: codeInvalid ? L("Ungültiger Code – 12 Zeichen, z. B. ABCD-EFGH-JKLM.", "Invalid code – 12 characters, e.g. ABCD-EFGH-JKLM.") : nil)
                    }
                    LabeledContent {
                        PeerStatus(hub: store.peers)
                    } label: {
                        SettingLabel(L("Status", "Status"), "wifi", .green)
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
                    .onChange(of: floating) { store.office.applyPrefs() }
                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(value: $opacity, in: 0.4...1).frame(width: 150)
                            .onChange(of: opacity) { store.office.applyPrefs() }
                        Text(percentText(Int((opacity * 100).rounded()))).monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                } label: {
                    SettingLabel(L("Deckkraft", "Opacity"), "circle.lefthalf.filled", .gray)
                }
                Toggle(isOn: $daylight) { SettingLabel(L("Himmel folgt der Tageszeit", "Sky follows time of day"), "sun.horizon.fill", .cyan) }
            }

            Section {
                VersionRow(updater: store.updater)
                LabeledContent {
                    Button(copied ? L("Kopiert", "Copied") : L("Diagnose kopieren", "Copy Diagnostics")) {
                        copy(store.diagnostics())
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    }
                } label: {
                    SettingLabel(L("Diagnose", "Diagnostics"), "stethoscope", .gray,
                                 note: L("Für Fehlerberichte – enthält Projektnamen und letzte Tätigkeit.", "For bug reports – includes project names and the latest activity."))
                }
            }
        }
        .formStyle(.grouped)
        .task {
            #if !SNAPSHOT
            // Bei jedem Öffnen nachsehen – wer Mitteilungen in macOS abgelehnt hat, erfährt sonst nie, warum nichts kommt
            let s = await UNUserNotificationCenter.current().notificationSettings()
            notificationsDenied = s.authorizationStatus == .denied
            #endif
        }
        .frame(width: 500)
        .frame(minHeight: height ?? 420, idealHeight: height ?? 680, maxHeight: height ?? .infinity)
    }

    private func hourPicker(_ value: Binding<Int>) -> some View {
        Picker("", selection: value) {
            ForEach(0..<24, id: \.self) { h in Text(String(format: "%02d:00", h)).tag(h) }
        }
        .labelsHidden().fixedSize()
    }
}

/// Bereich der Systemeinstellungen öffnen (z. B. "com.apple.preference.security?Privacy_LocalNetwork").
func openSettings(_ pane: String) {
    if let url = URL(string: "x-apple.systempreferences:" + pane) { NSWorkspace.shared.open(url) }
}

extension SettingsView {
    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

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
        if let p = hub.problem {
            VStack(alignment: .trailing, spacing: 4) {
                Text(p).foregroundStyle(.orange).multilineTextAlignment(.trailing)
                Button(L("Lokales Netzwerk erlauben …", "Allow Local Network…")) { openSettings("com.apple.preference.security?Privacy_LocalNetwork") }
            }
        } else {
            Text(names.isEmpty ? L("Nicht verbunden – suche …", "Not connected – searching…")
                               : L("Verbunden mit ", "Connected to ") + names.joined(separator: ", "))
                .foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
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

/// Version mit „Nach Updates suchen“; bei einem Update aufklappbare Neuerungen.
private struct VersionRow: View {
    @ObservedObject var updater: Updater
    @State private var showNotes = false

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                status
                action
            }
        } label: {
            SettingLabel("Version \(AppInfo.version)", "info", .gray)
        }
        if case .available(_, let notes) = updater.state, !notes.isEmpty {
            DisclosureGroup(L("Was ist neu?", "What’s New?"), isExpanded: $showNotes) {
                Text(notes).font(.system(size: 12)).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch updater.state {
        case .checking:
            ProgressView().controlSize(.small)
        case .upToDate:
            Text(L("Aktuell", "Up to date")).foregroundStyle(.secondary)
        case .installing(let text):
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(.secondary)
        case .failed(let msg):
            Text(msg).foregroundStyle(.orange).lineLimit(2).multilineTextAlignment(.trailing)
        case .available, .idle:
            EmptyView()
        }
    }

    @ViewBuilder private var action: some View {
        switch updater.state {
        case .available(let v, _):
            Button(L("Auf \(v) aktualisieren", "Update to \(v)")) { Task { await updater.install() } }
                .buttonStyle(.borderedProminent)
        case .installing, .checking:
            EmptyView()
        default:
            Button(L("Nach Updates suchen", "Check for Updates")) { Task { await updater.check() } }
        }
    }
}

/// Tastenkürzel als Tastenkappe (nur Anzeige).
private struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12, weight: .medium)).monospaced()
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            .accessibilityLabel("Control-Option-A")
    }
}
