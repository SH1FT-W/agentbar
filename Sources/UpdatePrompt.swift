import SwiftUI

/// Beim Start: eigenes kleines Fenster, wenn eine neue Version bereit liegt – mit „Jetzt installieren“, „Später“
/// und „Diese Version überspringen“. Später = beim nächsten Start wieder fragen; Überspringen = erst bei der nächsten Version.
@MainActor
final class UpdatePromptController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(_ updater: Updater) {
        // Nie den Fokus klauen: wer gerade tippt, würde sonst mit Return „Jetzt installieren“ auslösen.
        // Das Fenster liegt nur vorn – erst ein Klick hinein macht es aktiv.
        if let window { window.orderFrontRegardless(); return }
        let view = UpdatePromptView(updater: updater) { [weak self] in self?.close() }
        let host = NSHostingView(rootView: view)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = L("Update", "Update")
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.contentView = host
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.center()
        window = w
        w.orderFrontRegardless()
    }

    func close() { window?.close() }

    func windowWillClose(_ notification: Notification) { window = nil }
}

struct UpdatePromptView: View {
    @ObservedObject var updater: Updater
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 20)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var content: some View {
        switch updater.state {
        case .available(let v, let notes):
            VStack(alignment: .leading, spacing: 3) {
                Text(L("AgentBar \(v) ist da", "AgentBar \(v) is available")).font(.system(size: 15, weight: .semibold))
                Text(L("Du hast Version \(AppInfo.version). Das Update dauert nur ein paar Sekunden, danach startet AgentBar neu.",
                       "You have version \(AppInfo.version). Updating takes a few seconds, then AgentBar relaunches."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !notes.isEmpty {
                ScrollView {
                    Text(Self.markdown(notes)).font(.system(size: 12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 160).fixedSize(horizontal: false, vertical: true)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            }
            HStack(spacing: 8) {
                Button(L("Überspringen", "Skip")) {
                    UserDefaults.standard.set(v, forKey: Prefs.updateSkipped)
                    dismiss()
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help(L("Diese Version nicht mehr anbieten – erst die nächste", "Don’t offer this version again – only the next one"))
                Spacer(minLength: 8)
                Button(L("Später", "Later"), action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button(L("Jetzt installieren", "Install Now")) { Task { await updater.install() } }
                    .keyboardShortcut(.defaultAction).glassProminentButton()
            }
            .controlSize(.large)
            .padding(.top, 4)
        case .installing(let text):
            Text(L("AgentBar wird aktualisiert", "Updating AgentBar")).font(.system(size: 15, weight: .semibold))
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case .failed(let msg):
            Text(L("Update hat nicht geklappt", "The update didn’t work")).font(.system(size: 15, weight: .semibold))
            Text(msg).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L("Schließen", "Close"), action: dismiss).keyboardShortcut(.cancelAction)
                Button(L("Erneut versuchen", "Try Again")) { Task { await updater.check() } }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        case .checking:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("Suche nach Updates …", "Checking for updates…")).foregroundStyle(.secondary) }
        case .upToDate, .idle:
            Text(L("AgentBar ist aktuell", "AgentBar is up to date")).font(.system(size: 15, weight: .semibold))
            HStack { Spacer(); Button(L("OK", "OK"), action: dismiss).keyboardShortcut(.defaultAction) }.controlSize(.large)
        }
    }

    /// Release-Notizen sind Markdown (Listen, **fett**) – Zeilenumbrüche erhalten.
    static func markdown(_ s: String) -> AttributedString {
        // Listenstriche als Punkte – inline-Markdown kennt keine Listen
        let s = s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix("- ") || $0.hasPrefix("* ") ? "•  " + $0.dropFirst(2) : String($0) }.joined(separator: "\n")
        return (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
