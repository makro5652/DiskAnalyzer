import Observation
import SwiftUI

// MARK: - Farbschemata

enum AppTheme: String, CaseIterable, Identifiable {
    case navy, vibrant, balanced, dataDriven, playful, innovative

    var id: String { rawValue }

    var title: String {
        switch self {
        case .navy: "Nachtblau (bisher)"
        case .vibrant: "Vibrant Tech Startup Culture"
        case .balanced: "Balanced Dual Tone"
        case .dataDriven: "Data-Driven"
        case .playful: "Playful Professional"
        case .innovative: "Innovative Tech Marketing"
        }
    }

    /// Farbfelder für die Auswahl.
    var swatches: [UInt32] {
        switch self {
        case .navy: [0x005F88, 0x063D5F, 0xD6FF00, 0xFF4B9B, 0x0092FF]
        case .vibrant: [0x4A90E2, 0x50E3C2, 0xD0021B, 0xF5F7FA, 0x4A4A4A]
        case .balanced: [0x1E1E1E, 0xF5F5F5, 0x007ACC, 0xFFA300, 0x4B4B4B]
        case .dataDriven: [0x007ACC, 0xFFA500, 0x33CC99, 0xF0F0F0, 0x333333]
        case .playful: [0x007ACC, 0xFFB300, 0xF4C542, 0xF5F5F5, 0x282C34]
        case .innovative: [0x4A90E2, 0x7ED321, 0xD0021B, 0xF5F7FA, 0x4A4A4A]
        }
    }

    var tokens: ThemeTokens {
        switch self {
        case .navy:
            .navy
        case .vibrant:
            .derived(dark: false, background: 0xF5F7FA, foreground: 0x4A4A4A, accent: 0x4A90E2,
                     chart: [0x50E3C2, 0xD0021B, 0x4A90E2],
                     size: (RGB(hex: 0x4A4A4A), RGB(hex: 0x2F74C6), RGB(hex: 0xD0021B)))
        case .balanced:
            .derived(dark: true, background: 0x1E1E1E, foreground: 0xF5F5F5, accent: 0x007ACC,
                     chart: [0xFFA300, 0x007ACC, 0x4B4B4B],
                     size: (RGB(hex: 0xF5F5F5), RGB(hex: 0xFFD27A), RGB(hex: 0xFFA300)))
        case .dataDriven:
            .derived(dark: false, background: 0xF0F0F0, foreground: 0x333333, accent: 0x007ACC,
                     chart: [0xFFA500, 0x33CC99, 0x007ACC],
                     size: (RGB(hex: 0x333333), RGB(hex: 0x007ACC), RGB(hex: 0xC77F00)))
        case .playful:
            .derived(dark: true, background: 0x282C34, foreground: 0xF5F5F5, accent: 0x007ACC,
                     chart: [0xFFB300, 0x007ACC, 0xF4C542],
                     size: (RGB(hex: 0xF5F5F5), RGB(hex: 0xF4C542), RGB(hex: 0xFFB300)))
        case .innovative:
            .derived(dark: false, background: 0xF5F7FA, foreground: 0x4A4A4A, accent: 0x4A90E2,
                     chart: [0x7ED321, 0xD0021B, 0x4A90E2],
                     size: (RGB(hex: 0x4A4A4A), RGB(hex: 0x4F8F10), RGB(hex: 0xD0021B)))
        }
    }
}

struct ThemeTokens {
    var isDark: Bool
    var windowRGB: RGB
    var sidebarTop, sidebarBottom, panel, pathBar, divider: RGB
    var sidebarSelection, sidebarSelectionBorder, rowSelection, segmentTrack, segmentActive: RGB
    var action, checkbox, text, textSecondary, textTertiary: RGB
    var discInner, discOuter, discRing: RGB
    var chart: [RGB]
    var sizeStops: [(Double, RGB)]

    /// Das aus dem Vorbild abgeleitete Blau.
    static let navy = ThemeTokens(
        isDark: true,
        windowRGB: RGB(hex: 0x00203F),
        sidebarTop: RGB(hex: 0x005F88), sidebarBottom: RGB(hex: 0x004468),
        panel: RGB(hex: 0x063D5F), pathBar: RGB(hex: 0x032E4E), divider: RGB(hex: 0x001E3D),
        sidebarSelection: RGB(hex: 0x007FB6), sidebarSelectionBorder: RGB(hex: 0x449ECD),
        rowSelection: RGB(hex: 0x1A4C74), segmentTrack: RGB(hex: 0x174966), segmentActive: RGB(hex: 0x0075A7),
        action: RGB(hex: 0x0092FF), checkbox: RGB(hex: 0x0A84FF),
        text: RGB(r: 0.95, g: 0.97, b: 0.98), textSecondary: RGB(hex: 0xA9C4D6), textTertiary: RGB(hex: 0x7FA0B6),
        discInner: RGB(hex: 0x0E8ED6), discOuter: RGB(hex: 0x0677BB), discRing: RGB(hex: 0x87BAFF),
        chart: [0xD6FF00, 0xFF4B9B, 0xBBF9DD, 0x00F7B7, 0x0DD9F3, 0x007FFE, 0x1954FF, 0x7A5CFF, 0xFFC23D, 0xFF7A59]
            .map { RGB(hex: $0) },
        sizeStops: [
            (6.0, RGB(hex: 0xDCE7EE)),   // 1 MB
            (7.5, RGB(hex: 0xEFE9A8)),   // 30 MB
            (8.0, RGB(hex: 0xF3DB6C)),   // 100 MB
            (8.7, RGB(hex: 0xF5BB5A)),   // 500 MB
            (9.0, RGB(hex: 0xF49F5C)),   // 1 GB
            (9.6, RGB(hex: 0xF2716A)),   // 4 GB
        ])

    /// Leitet alle Flächen aus Hintergrund, Schriftfarbe und Akzent einer Fünf-Farben-Palette ab.
    static func derived(dark: Bool, background: UInt32, foreground: UInt32, accent: UInt32,
                        chart: [UInt32], size: (low: RGB, mid: RGB, high: RGB)) -> ThemeTokens {
        let bg = RGB(hex: background), fg = RGB(hex: foreground), ac = RGB(hex: accent)
        let shade = dark ? RGB.black : fg
        let base = chart.map { RGB(hex: $0) }
        // Aus den Palettenfarben werden hellere und dunklere Stufen, damit viele Segmente unterscheidbar bleiben.
        let steps = base + base.map { $0.mixed(with: .white, 0.35) } + base.map { $0.mixed(with: .black, 0.25) }
        return ThemeTokens(
            isDark: dark,
            windowRGB: bg.mixed(with: shade, dark ? 0.4 : 0.12),
            sidebarTop: bg.mixed(with: ac, dark ? 0.16 : 0.14),
            sidebarBottom: bg.mixed(with: ac, dark ? 0.06 : 0.05),
            panel: bg,
            pathBar: bg.mixed(with: shade, dark ? 0.25 : 0.05),
            divider: bg.mixed(with: shade, dark ? 0.55 : 0.14),
            sidebarSelection: bg.mixed(with: ac, dark ? 0.75 : 0.28),
            sidebarSelectionBorder: ac,
            rowSelection: bg.mixed(with: ac, dark ? 0.35 : 0.18),
            segmentTrack: bg.mixed(with: dark ? .white : fg, 0.10),
            segmentActive: bg.mixed(with: ac, dark ? 0.8 : 0.32),
            action: ac, checkbox: ac,
            text: fg,
            textSecondary: fg.mixed(with: bg, 0.2),
            textTertiary: fg.mixed(with: bg, 0.35),
            discInner: ac.mixed(with: .white, 0.12),
            discOuter: ac,
            discRing: ac.mixed(with: .white, 0.5),
            chart: steps,
            sizeStops: [(6.0, size.low), (8.5, size.mid), (9.6, size.high)])
    }
}

@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    var current: AppTheme {
        didSet {
            tokens = current.tokens
            UserDefaults.standard.set(current.rawValue, forKey: "colorTheme")
        }
    }
    private(set) var tokens: ThemeTokens

    private init() {
        let saved = UserDefaults.standard.string(forKey: "colorTheme").flatMap(AppTheme.init(rawValue:)) ?? .navy
        current = saved
        tokens = saved.tokens
    }
}

// MARK: - Auswahl oben rechts

struct ThemePicker: View {
    @State private var open = false

    var body: some View {
        CircleIconButton(symbol: "paintpalette", help: "Farbschema wechseln") { open.toggle() }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Farbschema")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 2)
                    ForEach(AppTheme.allCases) { ThemeRow(theme: $0) }
                }
                .padding(10)
                .frame(width: 330)
                .background(Theme.panel)
                .preferredColorScheme(Theme.colorScheme)
            }
    }
}

private struct ThemeRow: View {
    let theme: AppTheme
    @State private var hovering = false

    var body: some View {
        let active = ThemeStore.shared.current == theme
        Button { ThemeStore.shared.current = theme } label: {
            HStack(spacing: 10) {
                HStack(spacing: 0) {
                    ForEach(theme.swatches, id: \.self) { Color(hex: $0).frame(width: 16, height: 22) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.hairline))
                Text(theme.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if active {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(active ? Theme.rowSelection : hovering ? Theme.rowHover : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
