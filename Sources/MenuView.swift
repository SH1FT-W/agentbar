import SwiftUI

// MARK: - Dropdown (Aufbau wie die System-Menüs in macOS 26/27: WLAN, Bluetooth, Kontrollzentrum)

/// Maße der System-Menüs: Text sitzt 14 pt vom Rand, Zeilen-Hervorhebungen 5 pt.
enum MenuMetrics {
    static let width: CGFloat = 340
    static let inset: CGFloat = 14
    static let rowInset: CGFloat = 5
    static let rowPadding: CGFloat = 9          // rowInset + rowPadding = inset
    static let itemHeight: CGFloat = 24
    static let circle: CGFloat = 26
}

struct MenuView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var monitor: SessionMonitor
    @EnvironmentObject var quota: QuotaMonitor
    @EnvironmentObject var updater: Updater
    @AppStorage(Prefs.quotaEnabled) private var quotaEnabled = true
    @State private var expanded: String?
    /// Tastatur-/Maus-Auswahl in der Sitzungsliste (wie die Hervorhebung in NSMenu).
    @State private var selected: String?
    /// Menüfenster sichtbar? Steuert die Animationen – geschlossen läuft nichts weiter.
    @State private var visible = true
    @FocusState private var focused: Bool

    init(expanded: String? = nil) { _expanded = State(initialValue: expanded) }

    var body: some View {
        let list = monitor.visible
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.leading, MenuMetrics.inset).padding(.trailing, 10).padding(.top, 10).padding(.bottom, 8)

            if let msg = store.message {
                Notice(text: msg) { withAnimation(.snappy(duration: 0.2)) { store.message = nil } }
                    .padding(.horizontal, MenuMetrics.inset).padding(.bottom, 8)
            }
            if !store.hooksInstalled {
                HookHint().padding(.horizontal, 10).padding(.bottom, 8)
            }

            MenuSeparator()
            if list.isEmpty {
                EmptyAgents()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(list.filter { $0.device == nil }) { row($0) }
                            // Sitzungen anderer Macs darunter, je Gerät mit schlichter Überschrift
                            ForEach(devices(list), id: \.self) { d in
                                DeviceHeader(name: d, symbol: list.first { $0.device == d }?.deviceSymbol ?? "desktopcomputer")
                                ForEach(list.filter { $0.device == d }) { row($0) }
                            }
                        }
                        .padding(.horizontal, MenuMetrics.rowInset)
                    }
                    .scrollIndicators(.never)
                    // Bis sieben Zeilen wächst die Liste mit (auch aufgeklappt), darüber wird gescrollt
                    .frame(maxHeight: expanded == nil ? 330 : 560)
                    .fixedSize(horizontal: false, vertical: list.count <= 7)
                    .onChange(of: selected) { _, id in
                        if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
                    }
                }
            }

            QuotaSection()
            StatsSection()

            MenuSeparator()
            VStack(spacing: 0) {
                MenuItem(title: store.office.isOpen ? L("Büro schließen", "Close Office") : L("Büro öffnen", "Open Office"), icon: "building.2",
                         shortcut: "⌃⌥A") { store.office.toggle() }
                MenuItem(title: L("Einstellungen …", "Settings…"), icon: "gearshape", shortcut: "⌘,") { SettingsWindow.show(store) }
                    .keyboardShortcut(",")
                updateItem
                MenuItem(title: L("AgentBar beenden", "Quit AgentBar"), icon: "power", shortcut: "⌘Q") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(.horizontal, MenuMetrics.rowInset).padding(.bottom, 6)
        }
        .frame(width: MenuMetrics.width)
        .environment(\.menuVisible, visible)
        .background(WindowVisibility(visible: $visible))
        // Tastatur: ↑/↓ wählt, Return springt zur Sitzung, Leertaste klappt auf
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.downArrow) { move(1, in: list) }
        .onKeyPress(.upArrow) { move(-1, in: list) }
        .onKeyPress(.return) {
            guard let s = list.first(where: { $0.id == selected }), s.device == nil else { return .ignored }
            Focus.open(s); return .handled
        }
        .onKeyPress(.space) {
            guard let id = selected else { return .ignored }
            withAnimation(.snappy(duration: 0.22)) { expanded = expanded == id ? nil : id }
            return .handled
        }
        .onAppear { quota.refreshIfStale(); focused = true }
        .onChange(of: visible) { _, on in
            if on { quota.refreshIfStale(); focused = true } else { selected = nil }
        }
    }

    // MARK: Kopf

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                summaryText.font(.system(size: 13, weight: .semibold))
                    .contentTransition(.opacity)
                Text(detailLine).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 6)
            if QuotaSection.isVisible(quotaEnabled) {
                let v = QuotaSection.values(quota)
                QuotaRings(session: v.session?.percent, weekly: v.weekly?.percent)
                    .frame(width: 26, height: 26)
            }
            Button { monitor.rescan(); Task { await quota.refresh() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(quota.loading ? 360 : 0))
                    .animation(quota.loading ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                               value: quota.loading)
            }
            .glassCircleButton()
            .keyboardShortcut("r")
            .help(L("Neu laden (⌘R)", "Reload (⌘R)"))
            .accessibilityLabel(L("Neu laden", "Reload"))
        }
    }

    /// „2 arbeiten · 1 braucht dich“ – nur der Teil, der dich braucht, ist orange.
    private var summaryText: Text {
        let w = monitor.waitingCount, r = monitor.workingCount
        let working = r == 1 ? L("1 arbeitet", "1 working") : L("\(r) arbeiten", "\(r) working")
        let waiting = w == 1 ? L("1 braucht dich", "1 needs you") : L("\(w) brauchen dich", "\(w) need you")
        let waitText = Text(waiting).foregroundColor(AgentStatus.waiting.color)
        switch (r > 0, w > 0) {
        case (true, true): return Text(working + " · ") + waitText
        case (true, false): return Text(working)
        case (false, true): return waitText
        default: return Text(monitor.visible.isEmpty ? "AgentBar" : L("Alles ruhig", "All quiet"))
        }
    }

    /// Zweite Kopfzeile: Anzahl Sitzungen, ggf. auf wie vielen Macs.
    private var detailLine: String {
        let list = monitor.visible
        guard !list.isEmpty else { return L("Bereit", "Ready") }
        let n = list.count == 1 ? L("1 Sitzung", "1 session") : L("\(list.count) Sitzungen", "\(list.count) sessions")
        let macs = Set(list.compactMap(\.device)).count
        return macs == 0 ? n : n + " · " + (macs == 1 ? L("1 weiterer Mac", "1 other Mac") : L("\(macs) weitere Macs", "\(macs) other Macs"))
    }

    // MARK: Liste

    private func row(_ s: AgentSession) -> some View {
        SessionRow(session: s,
                   expanded: Binding(get: { expanded == s.id }, set: { expanded = $0 ? s.id : nil }),
                   selected: selected == s.id,
                   onHover: { inside in
                       if inside { selected = s.id } else if selected == s.id { selected = nil }
                   })
        .id(s.id)
    }

    /// Reihenfolge wie angezeigt: eigene Sitzungen, dann je Gerät.
    private func ordered(_ list: [AgentSession]) -> [AgentSession] {
        list.filter { $0.device == nil } + devices(list).flatMap { d in list.filter { $0.device == d } }
    }

    private func move(_ step: Int, in list: [AgentSession]) -> KeyPress.Result {
        let ids = ordered(list).map(\.id)
        guard !ids.isEmpty else { return .ignored }
        if let cur = selected, let i = ids.firstIndex(of: cur) {
            selected = ids[max(0, min(ids.count - 1, i + step))]
        } else {
            selected = step > 0 ? ids.first : ids.last
        }
        return .handled
    }

    private func devices(_ list: [AgentSession]) -> [String] {
        Array(Set(list.compactMap(\.device))).sorted()
    }

    // MARK: Update

    @ViewBuilder
    private var updateItem: some View {
        switch updater.state {
        case .available(let v, let notes):
            UpdateAvailableItem(version: v, notes: notes) { Task { await updater.install() } }
        case .installing(let text):
            MenuItem(title: text, icon: "arrow.down.app") {}.disabled(true)
        case .failed(let msg):
            MenuItem(title: L("Nach Updates suchen …", "Check for Updates…"), icon: "arrow.down.app", detail: "v\(AppInfo.version)") {
                Task { await updater.check() }
            }
            Text(msg).font(.system(size: 11)).foregroundStyle(AgentStatus.error.color)
                .lineLimit(2).padding(.leading, MenuMetrics.rowPadding + 24).padding(.trailing, MenuMetrics.rowPadding).padding(.bottom, 3)
        case .checking, .upToDate, .idle:
            // Die normale Suche steht in den Einstellungen – hier nur, wenn es etwas zu tun gibt.
            EmptyView()
        }
    }
}

/// „Update installieren“ plus aufklappbare Neuerungen (statt nur Tooltip).
struct UpdateAvailableItem: View {
    let version: String
    let notes: String
    let install: () -> Void
    @State private var showNotes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                MenuItem(title: L("Update auf \(version) installieren", "Install Update \(version)"), icon: "arrow.down.app.fill",
                         detail: "v\(AppInfo.version)", action: install)
                if !notes.isEmpty {
                    Button { withAnimation(.snappy(duration: 0.2)) { showNotes.toggle() } } label: {
                        Image(systemName: "info.circle").font(.system(size: 12))
                            .foregroundStyle(showNotes ? Color.accentColor : Color.secondary)
                            .frame(width: 24, height: MenuMetrics.itemHeight).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("Was ist neu?", "What’s New?"))
                    .accessibilityLabel(L("Was ist neu?", "What’s New?"))
                }
            }
            if showNotes {
                ScrollView {
                    Text(notes).font(.system(size: 11)).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: 140).fixedSize(horizontal: false, vertical: true)
                .padding(.leading, MenuMetrics.rowPadding + 24).padding(.trailing, MenuMetrics.rowPadding).padding(.bottom, 6)
                .transition(.opacity)
            }
        }
    }
}

/// Leerzustand: ruhig, mittig, mit Hinweis wo Agenten herkommen.
struct EmptyAgents: View {
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.07)).frame(width: 36, height: 36)
                Image(systemName: "sparkles").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
            }
            VStack(spacing: 2) {
                Text(L("Keine Sitzungen", "No sessions")).font(.system(size: 12, weight: .medium))
                Text(L("Sobald Claude Code läuft, erscheint die Sitzung hier.", "Sessions appear here as soon as Claude Code runs."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30).padding(.top, 6).padding(.bottom, 10)
        .accessibilityElement(children: .combine)
    }
}

/// Hinweis, solange die Claude-Code-Hooks fehlen – als ruhige Karte im Stil der Kontrollzentrum-Module.
struct HookHint: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Color.accentColor)
                Image(systemName: "scope").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: MenuMetrics.circle, height: MenuMetrics.circle)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Präzise Erkennung", "Precise Detection")).font(.system(size: 12, weight: .semibold))
                Text(L("Mit Hooks weiß AgentBar sofort, wann Claude auf dich wartet – statt zu raten.", "With hooks, AgentBar knows right away when Claude is waiting for you – no guessing."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("Einrichten", "Set Up")) { store.setHooks(true) }
                    .controlSize(.small).glassProminentButton()
                    .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - Sitzungszeile

struct SessionRow: View {
    let session: AgentSession
    @Binding var expanded: Bool
    var selected = false
    var onHover: (Bool) -> Void = { _ in }

    var body: some View {
        let s = session
        VStack(alignment: .leading, spacing: 0) {
            HoverRow(highlighted: selected, onHover: onHover, action: { withAnimation(.snappy(duration: 0.22)) { expanded.toggle() } }) {
                HStack(spacing: 10) {
                    StatusCircle(status: s.status)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(s.displayName).font(.system(size: 13)).lineLimit(1)
                            if s.title != nil, s.displayName != s.project {
                                Text(s.project).font(.system(size: 11)).foregroundStyle(.tertiary)
                                    .lineLimit(1).layoutPriority(-1)
                            }
                        }
                        HStack(spacing: 0) {
                            Text(subtitle).lineLimit(1).truncationMode(.tail)
                                .foregroundStyle(s.status == .waiting || s.status == .error ? s.status.color : Color.secondary)
                            if !s.subagents.isEmpty {
                                Text(" · \(helperText)").foregroundStyle(.secondary).fixedSize()
                            }
                        }
                        .font(.system(size: 11))
                    }
                    Spacer(minLength: 4)
                    meter
                    Chevron(open: expanded)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(s.displayName), \(s.status.label), \(subtitle)")
            .accessibilityHint(expanded ? L("Details ausblenden", "Hide details") : L("Details zeigen", "Show details"))
            .accessibilityAction(named: L("Zur Sitzung", "Go to Session")) { if s.device == nil { Focus.open(s) } }
            .contextMenu { if s.device == nil { actions } }
            if expanded { details.transition(.opacity.combined(with: .move(edge: .top))) }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(expanded ? 0.05 : 0)))
        .clipped()
    }

    /// Tokens kompakt + Kontext-Füllstand als Mini-Balken rechts in der Zeile.
    @ViewBuilder private var meter: some View {
        let s = session
        if s.totalTokens > 0 || s.contextFill != nil {
            VStack(alignment: .trailing, spacing: 3) {
                if s.totalTokens > 0 {
                    Text(formatTokens(s.totalTokens)).font(.system(size: 10)).foregroundStyle(.tertiary).monospacedDigit()
                }
                if let f = s.contextFill { ContextBar(fill: f, warning: s.contextWarning) }
            }
            .help(s.contextFill.map { L("Kontext", "Context") + " " + percentText(Int(($0 * 100).rounded())) + L(" von ", " of ") + s.contextWindowText } ?? "")
        }
    }

    private var helperText: String {
        let n = session.workingHelpers > 0 ? session.workingHelpers : session.subagents.count
        return n == 1 ? L("1 Helfer", "1 helper") : L("\(n) Helfer", "\(n) helpers")
    }

    private var subtitle: String {
        let s = session
        switch s.status {
        case .working: return s.activity.isEmpty ? L("Arbeitet …", "Working…") : s.activity
        // TODO(2.0-merge): s.waitingReason (Paket A) bevorzugen, z. B. „Möchte git push ausführen“ / „Hat eine Frage“.
        // Kein „Freigabe:“-Präfix mehr – Fragen und Pläne sind keine Freigaben; Farbe + Symbol zeigen den Zustand.
        case .waiting: return s.activity.isEmpty ? L("Wartet auf deine Freigabe", "Waiting for your approval") : s.activity
        default: return "\(s.status.label) · \(ago(s.lastActivity))"
        }
    }

    @ViewBuilder private var actions: some View {
        Button(L("Zur Sitzung", "Go to Session")) { Focus.open(session) }
        Button(L("Im Finder zeigen", "Show in Finder")) { Focus.showInFinder(session.cwd) }
        Button(L("Neues Terminal hier", "New Terminal Here")) { Focus.openTerminal(at: session.cwd) }
        Divider()
        Button(L("Sitzungs-ID kopieren", "Copy Session ID")) {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(session.id, forType: .string)
        }
    }

    private var details: some View {
        let s = session
        return VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                detail(L("Ordner", "Folder"), s.cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~"), middle: true)
                detail(L("Modell", "Model"), [shortModel(s.model), modeLabel(s.permissionMode)]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                detail(L("Läuft in", "Runs in"), hostName(s))
                detail("Tokens", formatTokens(s.totalTokens) + (s.cost.map { " · ≈ \(formatMoney($0))" } ?? ""))
                if let f = s.contextFill {
                    detail(L("Kontext", "Context"), percentText(Int((f * 100).rounded())) + L(" von ", " of ") + s.contextWindowText
                           + (s.contextWarning ? L(" · fast voll", " · almost full") : ""),
                           tint: s.contextWarning ? ContextBar.color(f, warning: true) : nil)
                }
                if !s.lastText.isEmpty { detail(L("Zuletzt", "Last"), s.lastText, lines: 3) }
            }
            if !s.subagents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(s.subagents.prefix(6)) { a in
                        HStack(spacing: 7) {
                            Circle().fill(a.working ? Color.accentColor : Color.primary.opacity(0.25))
                                .frame(width: 6, height: 6)
                            Text(a.type).font(.system(size: 11, weight: .medium))
                            Text(a.working ? a.activity : (a.description.isEmpty ? AgentStatus.done.label : a.description))
                                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if s.subagents.count > 6 {
                        Text(L("und \(s.subagents.count - 6) weitere", "and \(s.subagents.count - 6) more")).font(.system(size: 11)).foregroundStyle(.tertiary)
                            .padding(.leading, 13)
                    }
                }
            }
            if s.device == nil { buttons(s) }
        }
        // Einzug bündig mit dem Namen: Zeilen-Innenabstand + Kreis + Abstand
        .padding(.leading, MenuMetrics.rowPadding + MenuMetrics.circle + 10)
        .padding(.trailing, MenuMetrics.rowPadding).padding(.top, 1).padding(.bottom, 10)
    }

    private func buttons(_ s: AgentSession) -> some View {
        HStack(spacing: 6) {
            Button(L("Zur Sitzung", "Go to Session")) { Focus.open(s) }
            Spacer()
            Button { Focus.showInFinder(s.cwd) } label: { Image(systemName: "folder") }
                .help(L("Im Finder zeigen", "Show in Finder")).accessibilityLabel(L("Im Finder zeigen", "Show in Finder"))
            Button { Focus.openTerminal(at: s.cwd) } label: { Image(systemName: "terminal") }
                .help(L("Neues Terminal hier", "New Terminal Here")).accessibilityLabel(L("Neues Terminal hier", "New Terminal Here"))
        }
        .glassButton().controlSize(.small)
    }

    private func hostName(_ s: AgentSession) -> String {
        if let d = s.device { return "\(d) · \(s.source.label)" }
        guard let b = s.hostBundle, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) else { return s.source.label }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func detail(_ k: String, _ v: String, lines: Int = 1, middle: Bool = false, tint: Color? = nil) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(k).foregroundStyle(.tertiary).gridColumnAlignment(.leading)
            Text(v).foregroundStyle(tint ?? Color.secondary).lineLimit(lines).truncationMode(middle ? .middle : .tail)
        }
        .font(.system(size: 11))
    }
}

/// Kontext-Füllstand als schmaler Balken; orange ab der Warnschwelle, rot kurz vor voll.
struct ContextBar: View {
    let fill: Double
    let warning: Bool

    static func color(_ f: Double, warning: Bool) -> Color {
        if f >= 0.95 { return AgentStatus.error.color }
        return warning ? AgentStatus.waiting.color : Color.primary.opacity(0.35)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.primary.opacity(0.1))
            Capsule().fill(Self.color(fill, warning: warning))
                .frame(width: max(3, 28 * min(1, fill)))
        }
        .frame(width: 28, height: 3)
        .accessibilityHidden(true)
    }
}

// MARK: - Kontingent

struct QuotaValues {
    var session: QuotaWindow?
    var weekly: QuotaWindow?
    var plan: String?
    var problem: String?
    var forecast: QuotaForecast?
}

struct QuotaSection: View {
    @EnvironmentObject var quota: QuotaMonitor
    @AppStorage(Prefs.quotaEnabled) private var enabled = true

    #if SNAPSHOT
    /// Nur für Snapshots: feste Werte statt Abruf bei Anthropic.
    static var demo: QuotaValues?
    #endif

    static func values(_ quota: QuotaMonitor) -> QuotaValues {
        #if SNAPSHOT
        if let d = demo { return d }
        #endif
        return QuotaValues(session: quota.session, weekly: quota.weekly, plan: quota.plan, problem: quota.problem, forecast: quota.forecast)
    }

    static func isVisible(_ enabled: Bool) -> Bool {
        #if SNAPSHOT
        if demo != nil { return true }
        #endif
        return enabled
    }

    var body: some View {
        if Self.isVisible(enabled) {
            let v = Self.values(quota)
            MenuSeparator()
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: L("Kontingent", "Usage"), detail: v.plan.map { "Claude \($0)" })
                if v.session == nil, v.weekly == nil {
                    if let p = v.problem {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AgentStatus.waiting.color)
                            Text(p).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.system(size: 11))
                        .padding(.horizontal, MenuMetrics.inset).padding(.top, 2).padding(.bottom, 4)
                    } else {
                        // Noch kein Abruf: „Lädt …“ statt irreführender 0 %
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(L("Lädt …", "Loading…")).foregroundStyle(.secondary)
                        }
                        .font(.system(size: 11))
                        .padding(.horizontal, MenuMetrics.inset).padding(.top, 2).padding(.bottom, 4)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        quotaLine(L("5 Stunden", "5 hours"), v.session, RingColors.session)
                        quotaLine(L("Woche", "Week"), v.weekly, RingColors.weekly)
                        if v.session != nil, let f = v.forecast { forecastLine(f, reset: v.session?.resetsAt) }
                    }
                    .padding(.horizontal, MenuMetrics.inset).padding(.top, 1).padding(.bottom, 4)
                    // Abruf gerade gedrosselt/fehlgeschlagen: Werte bleiben stehen, aber man sieht, wie alt sie sind
                    if let p = v.problem {
                        Text(L("Stand \(ago(quota.lastFetch)) · ", "As of \(ago(quota.lastFetch)) · ") + p)
                            .font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(2)
                            .padding(.horizontal, MenuMetrics.inset).padding(.bottom, 4)
                    }
                }
            }
        }
    }

    private func quotaLine(_ title: String, _ w: QuotaWindow?, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7).alignmentGuide(.firstTextBaseline) { $0.height - 0.5 }
            Text(title).font(.system(size: 12))
            Spacer(minLength: 6)
            Text(w.flatMap { $0.resetsAt }.map { resetText($0) } ?? "")
                .font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit().lineLimit(1)
            Text(w.map { percentText(Int($0.percent.rounded())) } ?? "–")
                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .frame(minWidth: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    /// „Reicht bis ~16:40“ (orange, wenn vor dem Reset leer) oder „Reicht bis zum Reset“.
    private func forecastLine(_ f: QuotaForecast, reset: Date?) -> some View {
        let short: Date? = f.exhaustsAt.flatMap { at in (reset.map { at < $0 } ?? true) ? at : nil }
        let text: String
        if let at = short {
            let df = DateFormatter(); df.locale = Lang.locale; df.timeStyle = .short; df.dateStyle = .none
            text = L("Reicht bis ~\(df.string(from: at))", "Lasts until ~\(df.string(from: at))")
        } else {
            text = L("Reicht bis zum Reset", "Lasts until reset")
        }
        return HStack(spacing: 5) {
            Image(systemName: short == nil ? "checkmark.circle" : "hourglass")
            Text(text)
            if f.percentPerHour > 0 {
                Text("· " + L("\(Int(f.percentPerHour.rounded())) %/Std.", "\(Int(f.percentPerHour.rounded()))%/h"))
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(short == nil ? Color.secondary : AgentStatus.waiting.color)
        .padding(.leading, 13).padding(.top, 1)
        .accessibilityElement(children: .combine)
    }
}

enum RingColors {
    static let session = Color(red: 0.98, green: 0.07, blue: 0.31)   // wie der Bewegen-Ring
    static let weekly = Color(red: 0.61, green: 0.98, blue: 0.0)     // wie der Trainieren-Ring
}

/// Aktivitätsringe wie auf der Apple Watch: außen 5-Stunden-Fenster, innen Woche. nil = noch keine Daten.
struct QuotaRings: View {
    let session: Double?
    let weekly: Double?
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, line = w * 0.15, gap = w * 0.02
            ZStack {
                ring(session, RingColors.session, line).padding(line / 2)
                ring(weekly, RingColors.weekly, line).padding(line * 1.5 + gap)
            }
            .frame(width: w, height: w)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(L("Kontingent", "Usage"))
        .accessibilityValue(accessibilityText)
        .help(accessibilityText)
    }

    private var accessibilityText: String {
        func p(_ v: Double?) -> String { v.map { percentText(Int($0.rounded())) } ?? L("lädt", "loading") }
        return L("5 Stunden \(p(session)), Woche \(p(weekly))", "5 hours \(p(session)), week \(p(weekly))")
    }

    private func ring(_ pct: Double?, _ c: Color, _ line: CGFloat) -> some View {
        let p = max(0.001, min(pct ?? 0, 100) / 100)
        return ZStack {
            Circle().stroke(c.opacity(0.2), lineWidth: line)
            if pct != nil {
                Circle().trim(from: 0, to: p)
                    .stroke(AngularGradient(colors: [c.opacity(0.85), c], center: .center,
                                            startAngle: .zero, endAngle: .degrees(360 * p)),
                            style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

// MARK: - Bausteine

/// Überschrift für die Sitzungen eines anderen Macs in der Agenten-Liste.
struct DeviceHeader: View {
    let name: String
    let symbol: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(L("Auf \(name)", "On \(name)"))
        }
        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MenuMetrics.rowPadding).padding(.top, 8).padding(.bottom, 2)
        .accessibilityAddTraits(.isHeader)
    }
}

struct SectionHeader: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit() }
        }
        .padding(.horizontal, MenuMetrics.inset).padding(.top, 1).padding(.bottom, 4)
    }
}

struct MenuSeparator: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
            .padding(.horizontal, MenuMetrics.inset).padding(.vertical, 5)
            .accessibilityHidden(true)
    }
}

struct Notice: View {
    let text: String
    let close: () -> Void
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "info.circle.fill").foregroundStyle(Color.accentColor)
            Text(text).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: close) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless).foregroundStyle(.tertiary)
                .help(L("Ausblenden", "Hide")).accessibilityLabel(L("Ausblenden", "Hide"))
        }
        .font(.system(size: 11))
    }
}

// MARK: - Sichtbarkeit des Menüfensters

private struct MenuVisibleKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    /// false, solange das Menüfenster zu ist – Animationen pausieren dann.
    var menuVisible: Bool {
        get { self[MenuVisibleKey.self] }
        set { self[MenuVisibleKey.self] = newValue }
    }
}

/// Meldet, ob das umgebende Fenster sichtbar ist (MenuBarExtra-Fenster werden beim Schließen nur ausgeblendet,
/// die Ansicht lebt weiter – ohne das liefe die TimelineView der Arbeits-Punkte im Hintergrund weiter).
struct WindowVisibility: NSViewRepresentable {
    @Binding var visible: Bool

    func makeNSView(context: Context) -> Probe {
        let v = Probe()
        v.onChange = { on in if visible != on { visible = on } }
        return v
    }
    func updateNSView(_ nsView: Probe, context: Context) {}

    final class Probe: NSView {
        var onChange: ((Bool) -> Void)?
        private var token: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
            guard let w = window else { report(false); return }
            token = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                           object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.report(self?.window?.occlusionState.contains(.visible) ?? false) }
            }
            report(w.occlusionState.contains(.visible))
        }

        private func report(_ on: Bool) {
            DispatchQueue.main.async { [weak self] in self?.onChange?(on) }
        }

        deinit { if let token { NotificationCenter.default.removeObserver(token) } }
    }
}

struct StatusCircle: View {
    let status: AgentStatus
    @Environment(\.menuVisible) private var visible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(status.color)
            if status == .working && !reduceMotion {
                // Nur bei offenem Menü animieren; geschlossen pausiert die Timeline ganz.
                TimelineView(.animation(minimumInterval: 1 / 20, paused: !visible)) { t in
                    WorkingDots(time: t.date.timeIntervalSinceReferenceDate)
                }
            } else {
                Image(systemName: status.symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(status.glyph)
            }
        }
        .frame(width: MenuMetrics.circle, height: MenuMetrics.circle)
        .accessibilityElement()
        .accessibilityLabel(status.label)
    }
}

/// Drei hüpfende Punkte (wie „schreibt …“ in Nachrichten).
struct WorkingDots: View {
    let time: Double
    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3) { i in
                Circle().fill(.white).frame(width: 3.5, height: 3.5)
                    .offset(y: -2.2 * max(0, sin((time * 5) - Double(i) * 0.9)))
            }
        }
    }
}

/// Zeile mit dezenter Hervorhebung beim Überfahren oder per Tastatur (wie die Geräte-Zeilen im WLAN-/Bluetooth-Menü).
/// Echter Button, damit VoiceOver und Tastatur sie bedienen können.
struct HoverRow<Content: View>: View {
    var highlighted = false
    var onHover: (Bool) -> Void = { _ in }
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            content()
                .padding(.horizontal, MenuMetrics.rowPadding).padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle(highlighted: hover || highlighted))
        .onHover { hover = $0; onHover($0) }
        .animation(.easeOut(duration: 0.12), value: hover || highlighted)
    }
}

struct RowButtonStyle: ButtonStyle {
    let highlighted: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : highlighted ? 0.08 : 0)))
    }
}

struct Chevron: View {
    let open: Bool
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            .rotationEffect(.degrees(open ? 90 : 0))
            .accessibilityHidden(true)
    }
}

extension View {
    /// macOS 26/27: Liquid-Glass-Buttons, auf älteren Systemen normale umrandete Buttons.
    @ViewBuilder func glassButton() -> some View {
        if #available(macOS 26.0, *) { self.buttonStyle(.glass) } else { self.buttonStyle(.bordered) }
    }
    /// Hervorgehobener Glas-Button (Akzentfarbe) für die eine empfohlene Aktion.
    @ViewBuilder func glassProminentButton() -> some View {
        if #available(macOS 26.0, *) { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.borderedProminent) }
    }
    @ViewBuilder func glassCircleButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.small)
        } else {
            self.buttonStyle(.borderless)
        }
    }
}

/// Menüpunkt mit Akzent-Hervorhebung beim Überfahren (wie NSMenu).
struct MenuItem: View {
    let title: String
    let icon: String
    var detail: String? = nil
    var shortcut: String? = nil
    let action: () -> Void
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 12)).frame(width: 17)
                Text(title).font(.system(size: 13))
                Spacer(minLength: 6)
                if let detail { Text(detail).font(.system(size: 12)).opacity(hl ? 0.8 : 0.55) }
                if let shortcut { Text(shortcut).font(.system(size: 12)).opacity(hl ? 0.8 : 0.45) }
            }
            .foregroundStyle(hl ? Color.white : enabled ? Color.primary : Color.secondary)
            .padding(.horizontal, MenuMetrics.rowPadding).frame(height: MenuMetrics.itemHeight)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hl ? Color.accentColor : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(title)
    }

    private var hl: Bool { hover && enabled }
}
