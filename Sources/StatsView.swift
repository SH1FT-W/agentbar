import SwiftUI
import Charts

// MARK: - Statistik im Menü: „Heute“ + 7-Tage-Balken + Top-Projekte (aufklappbar)

struct StatsSection: View {
    @EnvironmentObject var stats: StatsStore
    @AppStorage("menuStatsExpanded") private var open = false
    @State private var hover = false

    var body: some View {
        let today = stats.today ?? DayStats(day: StatsStore.key(Date()))
        MenuSeparator()
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.snappy(duration: 0.22)) { open.toggle() } } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(L("Heute", "Today")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    if !open {
                        Text(summary(today)).font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit().lineLimit(1)
                    }
                    Chevron(open: open)
                }
                .padding(.horizontal, MenuMetrics.rowPadding).frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(hover ? 0.08 : 0)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .padding(.horizontal, MenuMetrics.rowInset)
            .accessibilityLabel(L("Statistik heute", "Today’s statistics") + ", " + summary(today))
            .accessibilityHint(open ? L("Einklappen", "Collapse") : L("Aufklappen", "Expand"))

            if open {
                StatsDetail(today: today, week: stats.last(7))
                    .padding(.horizontal, MenuMetrics.inset).padding(.top, 4).padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func summary(_ d: DayStats) -> String {
        guard d.tokens.total > 0 else { return L("Noch kein Verbrauch", "No usage yet") }
        return formatTokens(d.tokens.total) + " Tokens" + (d.cost > 0 ? " · ≈ \(formatMoney(d.cost))" : "")
    }
}

private struct StatsDetail: View {
    let today: DayStats
    let week: [DayStats]
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 0) {
                figure(formatTokens(today.tokens.total), "Tokens")
                figure(today.cost > 0 ? "≈ \(formatMoney(today.cost))" : "–", L("API-Gegenwert", "API value"))
                figure("\(today.sessions)", today.sessions == 1 ? L("Sitzung", "Session") : L("Sitzungen", "Sessions"))
            }
            chart
            projects
        }
    }

    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            Text(caption).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: 7 Tage

    private var chart: some View {
        let maxValue = max(1, week.map(\.tokens.total).max() ?? 0)
        let todayKey = StatsStore.key(Date())
        let empty = week.allSatisfy { $0.tokens.total == 0 }
        return VStack(alignment: .leading, spacing: 4) {
            Text(caption).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                .contentTransition(.opacity)
            Chart(week) { d in
                BarMark(x: .value("Day", d.day), y: .value("Tokens", d.tokens.total), width: .ratio(0.62))
                    .foregroundStyle(barColor(d, today: todayKey))
                    .cornerRadius(3)
                    .accessibilityLabel(longDay(d.day))
                    .accessibilityValue(formatTokens(d.tokens.total) + " Tokens")
            }
            .chartYScale(domain: 0...Double(maxValue) * 1.05)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let k = value.as(String.self) {
                            Text(shortDay(k)).font(.system(size: 10))
                                .foregroundStyle(k == todayKey ? Color.primary : Color.secondary)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { g in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let p):
                                let x = p.x - (proxy.plotFrame.map { g[$0].origin.x } ?? 0)
                                hovered = proxy.value(atX: x, as: String.self)
                            case .ended:
                                hovered = nil
                            }
                        }
                }
            }
            .overlay {
                if empty {
                    Text(L("Noch keine Daten", "No data yet")).font(.system(size: 11)).foregroundStyle(.tertiary)
                        .offset(y: -8)
                }
            }
            .frame(height: 64)
            .animation(.easeOut(duration: 0.12), value: hovered)
        }
    }

    private var caption: String {
        if let k = hovered, let d = week.first(where: { $0.day == k }) {
            return longDay(k) + " · " + formatTokens(d.tokens.total) + " Tokens" + (d.cost > 0 ? " · ≈ \(formatMoney(d.cost))" : "")
        }
        let total = week.reduce(0) { $0 + $1.tokens.total }
        let cost = week.reduce(0) { $0 + $1.cost }
        return L("7 Tage", "7 days") + " · " + formatTokens(total) + " Tokens" + (cost > 0 ? " · ≈ \(formatMoney(cost))" : "")
    }

    private func barColor(_ d: DayStats, today: String) -> Color {
        if let h = hovered { return h == d.day ? Color.accentColor : Color.primary.opacity(0.18) }
        return d.day == today ? Color.accentColor : Color.primary.opacity(0.25)
    }

    // MARK: Top-Projekte

    @ViewBuilder private var projects: some View {
        let top = today.byProject.sorted { $0.value > $1.value }.prefix(3)
        if !top.isEmpty {
            let total = max(1, today.byProject.values.reduce(0, +))
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Projekte heute", "Projects today")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(top), id: \.key) { p in
                    HStack(spacing: 8) {
                        Text(p.key).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 6)
                        ShareBar(share: Double(p.value) / Double(total))
                        Text(formatTokens(p.value)).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                            .frame(minWidth: 48, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Datum

    private func date(_ key: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: key)
    }
    private func shortDay(_ key: String) -> String {
        guard let d = date(key) else { return "" }
        let f = DateFormatter(); f.locale = Lang.locale; f.dateFormat = "EEEEEE"
        return f.string(from: d)
    }
    private func longDay(_ key: String) -> String {
        guard let d = date(key) else { return key }
        if Calendar.current.isDateInToday(d) { return L("Heute", "Today") }
        if Calendar.current.isDateInYesterday(d) { return L("Gestern", "Yesterday") }
        let f = DateFormatter(); f.locale = Lang.locale; f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f.string(from: d)
    }
}

private struct ShareBar: View {
    let share: Double
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.primary.opacity(0.1))
            Capsule().fill(Color.accentColor.opacity(0.7)).frame(width: max(3, 44 * min(1, share)))
        }
        .frame(width: 44, height: 4)
        .accessibilityHidden(true)
    }
}
