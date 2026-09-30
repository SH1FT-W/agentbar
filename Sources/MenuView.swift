import SwiftUI
import ServiceManagement

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
    @AppStorage(Prefs.keepAwake) private var keepAwake = KeepAwakeMode.off.rawValue
    @State private var loginItem = SMAppService.mainApp.status == .enabled
    @State private var expanded: String?

    init(expanded: String? = nil) { _expanded = State(initialValue: expanded) }

    var body: some View {
        let list = monitor.visible
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, MenuMetrics.inset).padding(.top, 12).padding(.bottom, 10)

            if let msg = store.message {
                Notice(text: msg) { withAnimation(.snappy(duration: 0.2)) { store.message = nil } }
                    .padding(.horizontal, MenuMetrics.inset).padding(.bottom, 10)
            }
            if !store.hooksInstalled {
                HookHint().padding(.horizontal, 10).padding(.bottom, 10)
            }

            MenuSeparator()
            SectionHeader(title: "Agenten", detail: list.isEmpty ? nil : "\(list.count)")
            if list.isEmpty {
                EmptyAgents()
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(list) { s in
                            SessionRow(session: s, expanded: Binding(get: { expanded == s.id },
                                                                     set: { expanded = $0 ? s.id : nil }))
                        }
                    }
                    .padding(.horizontal, MenuMetrics.rowInset)
                }
                .scrollIndicators(.never)
                // Bis sieben Zeilen wächst die Liste mit (auch aufgeklappt), darüber wird gescrollt
                .frame(maxHeight: expanded == nil ? 330 : 560)
                .fixedSize(horizontal: false, vertical: list.count <= 7)
            }

            QuotaSection()

            MenuSeparator()
            VStack(spacing: 0) {
                MenuItem(title: store.office.isOpen ? "Büro schließen" : "Büro öffnen", icon: "building.2",
                         shortcut: "⌃⌥A") { store.office.toggle() }
                KeepAwakeRow(mode: $keepAwake)
                    .onChange(of: keepAwake) { _ in store.updateKeepAwake() }
                ToggleRow(title: "Beim Anmelden starten", icon: "power",
                          isOn: Binding(get: { loginItem }, set: { _ in toggleLoginItem() }))
            }
            .padding(.horizontal, MenuMetrics.rowInset)

            MenuSeparator()
            VStack(spacing: 0) {
                MenuItem(title: "Einstellungen …", icon: "gearshape", shortcut: "⌘,") { SettingsWindow.show(store) }
                    .keyboardShortcut(",")
                updateItem
                MenuItem(title: "AgentBar beenden", icon: "xmark.rectangle", shortcut: "⌘Q") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(.horizontal, MenuMetrics.rowInset).padding(.bottom, 6)
        }
        .frame(width: MenuMetrics.width)
        .onAppear { quota.refreshIfStale() }
    }

    @ViewBuilder
    private var updateItem: some View {
        switch updater.state {
        case .available(let v, let notes):
            MenuItem(title: "Update auf v\(v) installieren", icon: "arrow.down.app.fill", detail: "v\(AppInfo.version)") {
                Task { await updater.install() }
            }
            .help(notes)
        case .installing(let text):
            MenuItem(title: text, icon: "arrow.down.app") {}.disabled(true)
        case .checking:
            MenuItem(title: "Suche Updates …", icon: "arrow.down.app", detail: "v\(AppInfo.version)") {}.disabled(true)
        case .failed(let msg):
            MenuItem(title: "Nach Updates suchen …", icon: "arrow.down.app", detail: "v\(AppInfo.version)") {
                Task { await updater.check() }
            }
            .help(msg)
            Text(msg).font(.system(size: 11)).foregroundStyle(AgentStatus.error.color)
                .lineLimit(2).padding(.horizontal, 33).padding(.bottom, 3)
        case .upToDate:
            MenuItem(title: "Nach Updates suchen …", icon: "arrow.down.app", detail: "v\(AppInfo.version) · aktuell") {
                Task { await updater.check() }
            }
        case .idle:
            MenuItem(title: "Nach Updates suchen …", icon: "arrow.down.app", detail: "v\(AppInfo.version)") {
                Task { await updater.check() }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("AgentBar").font(.system(size: 13, weight: .semibold))
                Text(summary).font(.system(size: 11))
                    .foregroundStyle(monitor.waitingCount > 0 ? AgentStatus.waiting.color : Color.secondary)
                    .contentTransition(.opacity)
            }
            Spacer()
            Button { monitor.rescan(); Task { await quota.refresh() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(quota.loading ? 360 : 0))
                    .animation(quota.loading ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                               value: quota.loading)
            }
            .glassCircleButton().help("Neu einlesen")
        }
    }

    private var summary: String {
        let w = monitor.waitingCount, r = monitor.workingCount
        var parts: [String] = []
        if w > 0 { parts.append(w == 1 ? "1 braucht dich" : "\(w) brauchen dich") }
        if r > 0 { parts.append(r == 1 ? "1 arbeitet" : "\(r) arbeiten") }
        if parts.isEmpty { return monitor.visible.isEmpty ? "Keine Sitzungen" : "Alles ruhig" }
        return parts.joined(separator: " · ")
    }

    private func toggleLoginItem() {
        do {
            if loginItem { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            store.message = "Anmeldeobjekt: \(error.localizedDescription)"
        }
        loginItem = SMAppService.mainApp.status == .enabled
    }
}

/// Leerzustand: ruhig, mittig, mit Hinweis wo Agenten herkommen.
struct EmptyAgents: View {
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.07)).frame(width: 40, height: 40)
                Image(systemName: "sparkles").font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary)
            }
            VStack(spacing: 2) {
                Text("Keine aktiven Agenten").font(.system(size: 12, weight: .medium))
                Text("Sobald Claude Code läuft, erscheint die Sitzung hier.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30).padding(.top, 8).padding(.bottom, 12)
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
            VStack(alignment: .leading, spacing: 2) {
                Text("Präzise Erkennung").font(.system(size: 12, weight: .semibold))
                Text("Mit Hooks weiß AgentBar sofort, wann Claude auf dich wartet – statt zu raten.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Einrichten") { store.setHooks(true) }
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

    var body: some View {
        let s = session
        VStack(alignment: .leading, spacing: 0) {
            HoverRow(action: { withAnimation(.snappy(duration: 0.22)) { expanded.toggle() } }) {
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
                    Chevron(open: expanded)
                }
            }
            .contextMenu { actions }
            if expanded { details.transition(.opacity.combined(with: .move(edge: .top))) }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(expanded ? 0.05 : 0)))
        .clipped()
    }

    private var helperText: String {
        let n = session.workingHelpers > 0 ? session.workingHelpers : session.subagents.count
        return n == 1 ? "1 Helfer" : "\(n) Helfer"
    }

    private var subtitle: String {
        let s = session
        switch s.status {
        case .working: return s.activity.isEmpty ? "Arbeitet …" : s.activity
        case .waiting: return s.activity.isEmpty ? "Wartet auf deine Freigabe" : "Freigabe: \(s.activity)"
        case .error: return "Fehler · \(ago(s.lastActivity))"
        default: return "\(s.status.label) · \(ago(s.lastActivity))"
        }
    }

    @ViewBuilder private var actions: some View {
        Button("Zur Sitzung springen") { Focus.open(session) }
        Button("Im Finder zeigen") { Focus.showInFinder(session.cwd) }
        Button("Neues Terminal hier") { Focus.openTerminal(at: session.cwd) }
        Divider()
        Button("Sitzungs-ID kopieren") {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(session.id, forType: .string)
        }
    }

    private var details: some View {
        let s = session
        return VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                detail("Ordner", s.cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~"), middle: true)
                detail("Modell", [shortModel(s.model), modeLabel(s.permissionMode)]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                detail("Läuft in", hostName(s))
                detail("Tokens", formatTokens(s.totalTokens) + (s.cost.map { " · ≈ \(formatMoney($0))" } ?? ""))
                if !s.lastText.isEmpty { detail("Zuletzt", s.lastText, lines: 3) }
            }
            if !s.subagents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(s.subagents.prefix(6)) { a in
                        HStack(spacing: 7) {
                            Circle().fill(a.working ? Color.accentColor : Color.primary.opacity(0.25))
                                .frame(width: 6, height: 6)
                            Text(a.type).font(.system(size: 11, weight: .medium))
                            Text(a.working ? a.activity : (a.description.isEmpty ? "Fertig" : a.description))
                                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    if s.subagents.count > 6 {
                        Text("und \(s.subagents.count - 6) weitere").font(.system(size: 11)).foregroundStyle(.tertiary)
                            .padding(.leading, 13)
                    }
                }
            }
            HStack(spacing: 6) {
                Button("Zur Sitzung") { Focus.open(s) }
                Spacer()
                Button { Focus.showInFinder(s.cwd) } label: { Image(systemName: "folder") }
                    .help("Im Finder zeigen")
                Button { Focus.openTerminal(at: s.cwd) } label: { Image(systemName: "terminal") }
                    .help("Neues Terminal hier")
            }
            .glassButton().controlSize(.small)
        }
        // Einzug bündig mit dem Namen: Zeilen-Innenabstand + Kreis + Abstand
        .padding(.leading, MenuMetrics.rowPadding + MenuMetrics.circle + 10)
        .padding(.trailing, MenuMetrics.rowPadding).padding(.top, 1).padding(.bottom, 10)
    }

    private func hostName(_ s: AgentSession) -> String {
        guard let b = s.hostBundle, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) else { return s.source.label }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func detail(_ k: String, _ v: String, lines: Int = 1, middle: Bool = false) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(k).foregroundStyle(.tertiary).gridColumnAlignment(.leading)
            Text(v).foregroundStyle(.secondary).lineLimit(lines).truncationMode(middle ? .middle : .tail)
        }
        .font(.system(size: 11))
    }
}

// MARK: - Kontingent

struct QuotaSection: View {
    @EnvironmentObject var quota: QuotaMonitor
    @AppStorage(Prefs.quotaEnabled) private var enabled = true

    #if SNAPSHOT
    /// Nur für Snapshots: feste Werte statt Abruf bei Anthropic.
    static var demo: (session: QuotaWindow?, weekly: QuotaWindow?, plan: String?, problem: String?)?
    #endif

    private var values: (session: QuotaWindow?, weekly: QuotaWindow?, plan: String?, problem: String?) {
        #if SNAPSHOT
        if let d = Self.demo { return d }
        #endif
        return (quota.session, quota.weekly, quota.plan, quota.problem)
    }

    private var visible: Bool {
        #if SNAPSHOT
        if Self.demo != nil { return true }
        #endif
        return enabled
    }

    var body: some View {
        if visible {
            let v = values
            MenuSeparator()
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Kontingent", detail: v.plan.map { "Claude \($0)" })
                if let p = v.problem, v.session == nil {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AgentStatus.waiting.color)
                        Text(p).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, MenuMetrics.inset).padding(.top, 2).padding(.bottom, 4)
                } else {
                    HStack(spacing: 14) {
                        QuotaRings(session: v.session?.percent ?? 0, weekly: v.weekly?.percent ?? 0)
                            .frame(width: 50, height: 50)
                        VStack(alignment: .leading, spacing: 7) {
                            quotaLine("5 Stunden", v.session, RingColors.session)
                            quotaLine("Woche", v.weekly, RingColors.weekly)
                        }
                    }
                    .padding(.horizontal, MenuMetrics.inset).padding(.top, 3).padding(.bottom, 4)
                }
            }
        }
    }

    private func quotaLine(_ title: String, _ w: QuotaWindow?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7).alignmentGuide(.firstTextBaseline) { $0.height - 0.5 }
                Text(title).font(.system(size: 12))
                Spacer(minLength: 4)
                Text(w.map { "\(Int($0.percent.rounded())) %" } ?? "–")
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            Text(w.flatMap { $0.resetsAt }.map { resetText($0) } ?? " ")
                .font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit()
                .padding(.leading, 13)
        }
    }
}

enum RingColors {
    static let session = Color(red: 0.98, green: 0.07, blue: 0.31)   // wie der Bewegen-Ring
    static let weekly = Color(red: 0.61, green: 0.98, blue: 0.0)     // wie der Trainieren-Ring
}

/// Aktivitätsringe wie auf der Apple Watch: außen 5-Stunden-Fenster, innen Woche.
struct QuotaRings: View {
    let session: Double
    let weekly: Double
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
    }

    private func ring(_ pct: Double, _ c: Color, _ line: CGFloat) -> some View {
        let p = max(0.001, min(pct, 100) / 100)
        return ZStack {
            Circle().stroke(c.opacity(0.2), lineWidth: line)
            Circle().trim(from: 0, to: p)
                .stroke(AngularGradient(colors: [c.opacity(0.85), c], center: .center,
                                        startAngle: .zero, endAngle: .degrees(360 * p)),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Bausteine

struct SectionHeader: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
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
                .buttonStyle(.borderless).foregroundStyle(.tertiary).help("Ausblenden")
        }
        .font(.system(size: 11))
    }
}

struct StatusCircle: View {
    let status: AgentStatus
    var body: some View {
        ZStack {
            Circle().fill(status.color)
            if status == .working {
                TimelineView(.animation(minimumInterval: 1 / 20)) { t in
                    WorkingDots(time: t.date.timeIntervalSinceReferenceDate)
                }
            } else {
                Image(systemName: status.symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(status.glyph)
            }
        }
        .frame(width: MenuMetrics.circle, height: MenuMetrics.circle)
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

/// Zeile mit dezenter Hervorhebung beim Überfahren (wie die Geräte-Zeilen im WLAN-/Bluetooth-Menü).
struct HoverRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hover = false
    var body: some View {
        content()
            .padding(.horizontal, MenuMetrics.rowPadding).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(hover ? 0.08 : 0)))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
    }
}

struct Chevron: View {
    let open: Bool
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            .rotationEffect(.degrees(open ? 90 : 0))
    }
}

/// Schalter-Zeile wie in den Kontrollzentrum-Modulen (Text links, kleiner Schalter rechts).
struct ToggleRow: View {
    let title: String
    var icon: String = "power"
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 12)).frame(width: 17)
            Text(title).font(.system(size: 13))
            Spacer()
            Toggle("", isOn: $isOn).toggleStyle(.switch).controlSize(.mini).labelsHidden()
        }
        .padding(.horizontal, MenuMetrics.rowPadding).frame(height: 28)
    }
}

/// „Wach bleiben“ als Menüpunkt mit Untermenü: Wert rechts, wie „Ton ›“ in den System-Menüs.
struct KeepAwakeRow: View {
    @Binding var mode: String
    @State private var hover = false

    private var current: KeepAwakeMode { KeepAwakeMode(rawValue: mode) ?? .off }
    private var short: String {
        switch current {
        case .off: return "Aus"
        case .auto: return "Bei Arbeit"
        case .always: return "Immer"
        }
    }

    var body: some View {
        Menu {
            Picker("Wach bleiben", selection: $mode) {
                ForEach(KeepAwakeMode.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.inline).labelsHidden()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: current == .off ? "cup.and.saucer" : "cup.and.saucer.fill")
                    .font(.system(size: 12)).frame(width: 17)
                Text("Wach bleiben").font(.system(size: 13))
                Spacer(minLength: 6)
                Text(short).font(.system(size: 12)).opacity(hover ? 0.8 : 0.55)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                    .opacity(hover ? 0.8 : 0.45)
            }
            .foregroundStyle(hover ? Color.white : Color.primary)
            .padding(.horizontal, MenuMetrics.rowPadding).frame(height: MenuMetrics.itemHeight)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hover ? Color.accentColor : .clear))
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .onHover { hover = $0 }
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
                if let detail { Text(detail).font(.system(size: 12)).opacity(0.55) }
                if let shortcut { Text(shortcut).font(.system(size: 12)).opacity(hl ? 0.8 : 0.45) }
            }
            .foregroundStyle(hl ? Color.white : enabled ? Color.primary : Color.secondary)
            .padding(.horizontal, MenuMetrics.rowPadding).frame(height: MenuMetrics.itemHeight)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hl ? Color.accentColor : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var hl: Bool { hover && enabled }
}
