import SwiftUI

// MARK: - Update window

enum UpdateWindow {
    /// The shared look of the "new version" window: hidden title bar, movable by its background,
    /// floating above other windows, centered, kept alive when closed. Call after the content is set
    /// so that centering uses the final size. Activation and focus stay with the app.
    @MainActor static func style(_ w: NSWindow, title: String) {
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.title = title
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.center()
    }
}

// MARK: - View building blocks

/// App icon on the left, the content column on the right: the frame of the update window.
struct UpdatePromptFrame<Content: View>: View {
    let width: CGFloat
    let insets: EdgeInsets
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable().frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(insets)
        .frame(width: width)
    }
}

/// Headline plus a smaller secondary line.
struct UpdatePromptHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Scrollable, selectable release notes on a faint card.
struct UpdateNotesBox: View {
    let text: Text
    var maxHeight: CGFloat = 160

    var body: some View {
        ScrollView {
            text.font(.system(size: 12))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(maxHeight: maxHeight).fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}
