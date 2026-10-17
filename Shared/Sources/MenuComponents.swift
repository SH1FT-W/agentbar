import SwiftUI

// MARK: - Menu geometry

/// Shared geometry of the dropdown menus, matching the system menus of macOS 26/27.
/// Apps add their own values in an extension (menu width, circle sizes and so on).
enum MenuMetrics {
    static let inset: CGFloat = 14
    static let rowPadding: CGFloat = 9
    static let itemHeight: CGFloat = 24
}

/// The few details in which the apps' menus still differ. Set once at the menu root with
/// `.menuLook(_:)`; everything below reads it from the environment. The defaults are the look
/// of the AgentBar menu (1 pt line as separator, digits in header details monospaced, details
/// and shortcuts brightened while a row is highlighted).
struct MenuLook {
    enum Separator { case line, divider }
    var separator: Separator = .line
    var headerTopPadding: CGFloat = 1
    var headerBottomPadding: CGFloat = 4
    var headerMonospacedDigits = true
    /// Opacity of the detail text in a MenuItem that is not highlighted.
    var detailOpacity: Double = 0.55
    /// Opacity of the keyboard shortcut in a MenuItem that is not highlighted.
    var shortcutOpacity: Double = 0.45
    /// Opacity of detail and shortcut while the row is highlighted (white on accent color).
    var highlightedOpacity: Double = 0.8
}

private struct MenuLookKey: EnvironmentKey {
    static let defaultValue = MenuLook()
}

extension EnvironmentValues {
    var menuLook: MenuLook {
        get { self[MenuLookKey.self] }
        set { self[MenuLookKey.self] = newValue }
    }
}

extension View {
    /// Sets the look of the shared menu components for this view tree.
    func menuLook(_ look: MenuLook) -> some View { environment(\.menuLook, look) }
}

// MARK: - Shapes and glass

/// Card and row shape in the menu: from macOS 26 on concentric to the window corners (follows the
/// system, including the corners unified in macOS 27); `minimum` keeps the previous radius as a floor.
func cardShape(_ minimum: CGFloat) -> AnyShape {
    if #available(macOS 26.0, *) {
        return AnyShape(ConcentricRectangle(corners: .concentric(minimum: .fixed(minimum)), isUniform: true))
    }
    return AnyShape(RoundedRectangle(cornerRadius: minimum, style: .continuous))
}

extension View {
    /// macOS 26/27: Liquid Glass button, on older systems a normal bordered button.
    @ViewBuilder func glassButton() -> some View {
        if #available(macOS 26.0, *) { self.buttonStyle(.glass) } else { self.buttonStyle(.bordered) }
    }

    /// Prominent glass button (accent color) for the one recommended action.
    @ViewBuilder func glassProminentButton() -> some View {
        #if SNAPSHOT
        // Rendered offscreen (snapshot tools) .glassProminent paints the whole window blank; the
        // screenshots use the ordinary prominent button instead.
        self.buttonStyle(.borderedProminent)
        #else
        if #available(macOS 26.0, *) { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.borderedProminent) }
        #endif
    }

    /// macOS 26/27: round Liquid Glass button, on older systems borderless.
    @ViewBuilder func glassCircleButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.small)
        } else {
            self.buttonStyle(.borderless)
        }
    }
}

// MARK: - Building blocks

/// Small section title with an optional detail on the right.
struct SectionHeader: View {
    let title: String
    var detail: String? = nil
    @Environment(\.menuLook) private var look

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let detail {
                let text = Text(detail).font(.system(size: 11)).foregroundStyle(.tertiary)
                if look.headerMonospacedDigits { text.monospacedDigit() } else { text }
            }
        }
        .padding(.horizontal, MenuMetrics.inset).padding(.top, look.headerTopPadding).padding(.bottom, look.headerBottomPadding)
    }
}

/// Separator between menu sections.
struct MenuSeparator: View {
    @Environment(\.menuLook) private var look

    var body: some View {
        switch look.separator {
        case .line:
            Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
                .padding(.horizontal, MenuMetrics.inset).padding(.vertical, 5)
                .accessibilityHidden(true)
        case .divider:
            Divider().padding(.horizontal, MenuMetrics.inset).padding(.vertical, 5)
        }
    }
}

/// Command row like a native menu entry (macOS 26: symbol on the left, accent highlight on hover,
/// optional check mark, detail text and keyboard shortcut).
struct MenuItem: View {
    let title: String
    let icon: String
    var checked: Bool? = nil
    var detail: String? = nil
    var shortcut: String? = nil
    let action: () -> Void
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.menuLook) private var look

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 12)).frame(width: 17)
                Text(title).font(.system(size: 13))
                Spacer(minLength: 6)
                if let detail { Text(detail).font(.system(size: 12)).opacity(hl ? look.highlightedOpacity : look.detailOpacity) }
                if let shortcut { Text(shortcut).font(.system(size: 12)).opacity(hl ? look.highlightedOpacity : look.shortcutOpacity) }
                if checked == true { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)) }
            }
            .foregroundStyle(hl ? Color.white : enabled ? Color.primary : Color.secondary)
            .padding(.horizontal, MenuMetrics.rowPadding).frame(height: MenuMetrics.itemHeight)
            .background(cardShape(7).fill(hl ? Color.accentColor : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(title)
    }

    private var hl: Bool { hover && enabled }
}
