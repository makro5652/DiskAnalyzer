import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum Theme {
    private static var t: ThemeTokens { ThemeStore.shared.tokens }

    static var isDark: Bool { t.isDark }
    static var colorScheme: ColorScheme { t.isDark ? .dark : .light }
    static var chart: [RGB] { t.chart }
    static var window: Color { t.windowRGB.color }
    static var sidebarTop: Color { t.sidebarTop.color }
    static var sidebarBottom: Color { t.sidebarBottom.color }
    static var panel: Color { t.panel.color }
    static var pathBar: Color { t.pathBar.color }
    static var divider: Color { t.divider.color }
    static var sidebarSelection: Color { t.sidebarSelection.color }
    static var sidebarSelectionBorder: Color { t.sidebarSelectionBorder.color }
    static var rowSelection: Color { t.rowSelection.color }
    static var segmentTrack: Color { t.segmentTrack.color }
    static var segmentActive: Color { t.segmentActive.color }
    static var action: Color { t.action.color }
    static var checkbox: Color { t.checkbox.color }
    static var text: Color { t.text.color }
    static var textSecondary: Color { t.textSecondary.color }
    static var textTertiary: Color { t.textTertiary.color }
    static var discInner: Color { t.discInner.color }
    static var discOuter: Color { t.discOuter.color }
    static var discRing: Color { t.discRing.color }

    /// Feine Linien und Flächen, die sich mit der Schriftfarbe an helle und dunkle Schemata anpassen.
    static var hairline: Color { t.text.color.opacity(0.14) }
    static var panelBorder: Color { t.text.color.opacity(0.10) }
    static var rowHover: Color { t.text.color.opacity(0.06) }
    static var circleButton: Color { t.text.color.opacity(0.10) }
    static var selectionOutline: Color { t.isDark ? .white : t.text.color }

    /// Färbt Größenangaben logarithmisch: je größer, desto auffälliger.
    static func sizeColor(_ bytes: Int64) -> Color {
        let stops = t.sizeStops
        let v = log10(Double(max(bytes, 1)))
        if v <= stops[0].0 { return stops[0].1.color }
        for (a, b) in zip(stops, stops.dropFirst()) where v <= b.0 {
            return a.1.mixed(with: b.1, (v - a.0) / (b.0 - a.0)).color
        }
        return stops[stops.count - 1].1.color
    }
}

/// Einfache RGB-Farbe, mit der sich Abstufungen fürs Diagramm rechnen lassen.
struct RGB: Equatable {
    var r: Double, g: Double, b: Double

    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    var color: Color { Color(red: r, green: g, blue: b) }

    func mixed(with o: RGB, _ t: Double) -> RGB {
        RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
    }

    static let white = RGB(r: 1, g: 1, b: 1)
    static let black = RGB(r: 0, g: 0, b: 0)
}

enum IconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(image, forKey: key)
        return image
    }
}

// MARK: - Bausteine

struct PanelBackground: ViewModifier {
    var fill: AnyShapeStyle = AnyShapeStyle(Theme.panel)

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.panelBorder))
    }
}

struct CircleIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .frame(width: 34, height: 34)
                .background(Theme.circleButton, in: Circle())
                .overlay(Circle().strokeBorder(Theme.hairline))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct CheckBox: View {
    let checked: Bool
    var covered = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(checked || covered ? Theme.checkbox.opacity(covered ? 0.45 : 1) : Color.white.opacity(0.03))
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(checked || covered ? Color.clear : Theme.textTertiary.opacity(0.75), lineWidth: 1)
                if checked || covered {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 16, height: 16)
            .padding(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(covered)
    }
}

/// Bereich, an dem sich das randlose Fenster ziehen lässt.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Randloses Fenster, Ampel-Knöpfe sitzen mittig im Kopf der Seitenleiste.
struct WindowConfigurator: NSViewRepresentable {
    let theme: AppTheme

    /// Hält die Ampel-Knöpfe an ihrem Platz, auch wenn macOS sie beim Größenändern neu anordnet.
    final class Coordinator {
        private static let firstX: CGFloat = 26
        private static let spacing: CGFloat = 23
        private static let centerFromTop: CGFloat = 39   // Mitte der Kopfzeile: 8 Rand + 62 / 2
        private var observers: [NSObjectProtocol] = []
        private var isPlacing = false

        func attach(to window: NSWindow) {
            let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
                .compactMap { window.standardWindowButton($0) }
            for button in buttons {
                button.postsFrameChangedNotifications = true
                observers.append(NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification, object: button, queue: .main
                ) { [weak self, weak window] _ in
                    if let window { self?.place(in: window) }
                })
            }
            place(in: window)
        }

        private func place(in window: NSWindow) {
            // setFrameOrigin löst selbst wieder die Benachrichtigung aus.
            guard !isPlacing, !window.styleMask.contains(.fullScreen) else { return }
            isPlacing = true
            defer { isPlacing = false }
            let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
                .compactMap { window.standardWindowButton($0) }
            guard let container = buttons.first?.superview else { return }
            for (i, button) in buttons.enumerated() {
                let target = NSPoint(x: Self.firstX + CGFloat(i) * Self.spacing,
                                     y: container.frame.height - Self.centerFromTop - button.frame.height / 2)
                if button.frame.origin != target { button.setFrameOrigin(target) }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            guard let w = view.window else { return }
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.styleMask.insert(.fullSizeContentView)
            w.titlebarSeparatorStyle = .none
            Self.apply(ThemeStore.shared.tokens, to: w)
            w.toolbar = NSToolbar()
            w.toolbarStyle = .unified
            coordinator.attach(to: w)
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        if let w = nsView.window { Self.apply(theme.tokens, to: w) }
    }

    private static func apply(_ tokens: ThemeTokens, to window: NSWindow) {
        let c = tokens.windowRGB
        window.backgroundColor = NSColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
        window.appearance = NSAppearance(named: tokens.isDark ? .darkAqua : .aqua)
    }
}
