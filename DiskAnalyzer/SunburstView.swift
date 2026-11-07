import SwiftUI

struct Arc {
    let node: FileNode
    let depth: Int
    let start: Double   // Radiant, 0 = oben, im Uhrzeigersinn
    let end: Double
    let tone: RGB
}

enum SunburstLayout {
    static let maxDepth = 5
    static let minAngle = 0.006

    /// Innerster Ring beginnt mit der ersten Schemafarbe, der zweite mit der nächsten; die Reihenfolge folgt der Größe.
    static func compute(root: FileNode) -> [Arc] {
        guard root.size > 0 else { return [] }
        let palette = Theme.chart
        var out: [Arc] = []

        func tone(rank i: Int, depth: Int, parentIndex: Int, parentTone: RGB) -> (RGB, Int) {
            switch depth {
            case 1:
                let idx = i % palette.count
                return (palette[idx], idx)
            case 2:
                var idx = (i + 1) % palette.count
                if idx == parentIndex { idx = (idx + 1) % palette.count }
                return (palette[idx], idx)
            default:
                // Äußere Ringe bleiben im Farbton des Sektors und werden abwechselnd heller und dunkler.
                let shade = [0.08, 0.20, -0.08, 0.30, -0.15][i % 5]
                let toned = shade >= 0 ? parentTone.mixed(with: .white, shade) : parentTone.mixed(with: .black, -shade)
                return (toned, parentIndex)
            }
        }

        func walk(_ node: FileNode, depth: Int, start: Double, span: Double, parentIndex: Int, parentTone: RGB) {
            guard depth <= maxDepth, node.size > 0 else { return }
            var a = start
            for (i, c) in node.children.enumerated() {
                let w = Double(c.size) / Double(node.size) * span
                if w < minAngle { break }   // Kinder sind nach Größe sortiert
                let (t, idx) = tone(rank: i, depth: depth, parentIndex: parentIndex, parentTone: parentTone)
                out.append(Arc(node: c, depth: depth, start: a, end: a + w, tone: t))
                if c.isDirectory { walk(c, depth: depth + 1, start: a, span: w, parentIndex: idx, parentTone: t) }
                a += w
            }
        }
        walk(root, depth: 1, start: 0, span: 2 * .pi, parentIndex: -1, parentTone: palette[0])
        return out
    }
}

private struct Geo {
    let center: CGPoint
    let outer: CGFloat
    let inner: CGFloat
    let ring: CGFloat

    init(size: CGSize) {
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        outer = max(10, min(size.width, size.height) / 2 - 24)
        inner = outer * 0.4
        ring = (outer - inner) / CGFloat(SunburstLayout.maxDepth)
    }

    func point(_ r: CGFloat, _ a: Double) -> CGPoint {
        CGPoint(x: center.x + r * CGFloat(sin(a)), y: center.y - r * CGFloat(cos(a)))
    }

    func segment(depth: Int, start: Double, end: Double) -> Path {
        let r1 = inner + ring * CGFloat(depth - 1)
        let r2 = r1 + ring
        let steps = max(2, Int(((end - start) / (.pi / 90)).rounded(.up)))
        var p = Path()
        for i in 0...steps {
            let pt = point(r2, start + (end - start) * Double(i) / Double(steps))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        for i in (0...steps).reversed() {
            p.addLine(to: point(r1, start + (end - start) * Double(i) / Double(steps)))
        }
        p.closeSubpath()
        return p
    }

    enum Hit { case center, arc(Int), none }

    func hit(_ p: CGPoint, arcs: [Arc]) -> Hit {
        let dx = p.x - center.x, dy = p.y - center.y
        let r = hypot(dx, dy)
        if r < inner { return .center }
        if r > outer { return .none }
        var theta = atan2(Double(dx), Double(-dy))
        if theta < 0 { theta += 2 * .pi }
        let depth = Int((r - inner) / ring) + 1
        for (i, a) in arcs.enumerated() where a.depth == depth && theta >= a.start && theta < a.end {
            return .arc(i)
        }
        return .none
    }
}

struct SunburstView: View {
    @Bindable var model: AppModel
    @State private var arcs: [Arc] = []
    @State private var hoverID: String?

    private struct LayoutKey: Equatable {
        var id: String?
        var revision: Int
        var theme: AppTheme
    }

    var body: some View {
        GeometryReader { proxy in
            let geo = Geo(size: proxy.size)
            ZStack {
                RadialGradient(colors: [Theme.discOuter.opacity(0.22), .clear],
                               center: .center, startRadius: geo.inner, endRadius: geo.outer * 1.35)
                Canvas { ctx, _ in draw(ctx, geo) }
                centerLabel(geo)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    if case .arc(let i) = geo.hit(p, arcs: arcs) { hoverID = arcs[i].node.id } else { hoverID = nil }
                case .ended:
                    hoverID = nil
                }
            }
            .gesture(
                SpatialTapGesture(count: 1).onEnded { tap in
                    let additive = NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift)
                    switch geo.hit(tap.location, arcs: arcs) {
                    case .center: model.goUp()
                    case .arc(let i):
                        let n = arcs[i].node
                        // Klick: Eintrag aufrufen. Cmd/Shift-Klick: an- oder abhaken.
                        if additive { model.toggleChecked(n) } else { model.activate(n) }
                    case .none: break
                    }
                }
            )
            .contextMenu {
                if let node = hoverID.flatMap({ model.index[$0] }) {
                    NodeActions(model: model, node: node)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    model.colorMode = model.colorMode == .folder ? .kind : .folder
                } label: {
                    Image(systemName: model.colorMode == .folder ? "circle.hexagongrid" : "circle.hexagongrid.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.colorMode == .folder ? "Nach Dateityp färben" : "Nach Ordnern färben")
                .padding(10)
            }
            .overlay(alignment: .bottomLeading) {
                if model.colorMode == .kind { legend }
            }
        }
        .onChange(of: LayoutKey(id: model.chartCenter?.id, revision: model.revision, theme: ThemeStore.shared.current), initial: true) {
            arcs = model.chartCenter.map(SunburstLayout.compute) ?? []
            hoverID = nil
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(FileKind.allCases) { k in
                HStack(spacing: 5) {
                    Circle().fill(k.color).frame(width: 8, height: 8)
                    Text(k.label).font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            HStack(spacing: 5) {
                Circle().fill(Color(hue: 0.6, saturation: 0.15, brightness: 0.55)).frame(width: 8, height: 8)
                Text("Ordner").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(10)
        .allowsHitTesting(false)
    }

    private func color(_ a: Arc, hovered: Bool) -> Color {
        let tone: RGB
        if model.colorMode == .kind {
            let n = a.node
            if n.isDirectory {
                tone = RGB(hex: 0x3F6E8F).mixed(with: .white, 0.05 * Double(a.depth - 1))
            } else {
                let c = NSColor(n.kind.color).usingColorSpace(.sRGB) ?? .gray
                tone = RGB(r: c.redComponent, g: c.greenComponent, b: c.blueComponent)
            }
        } else {
            tone = a.tone
        }
        return (hovered ? tone.mixed(with: .white, 0.35) : tone).color
    }

    private func draw(_ ctx: GraphicsContext, _ geo: Geo) {
        let selection = model.selection
        var selected: [Path] = []
        for a in arcs {
            let path = geo.segment(depth: a.depth, start: a.start, end: a.end)
            ctx.fill(path, with: .color(color(a, hovered: a.node.id == hoverID)))
            if a.depth > 1 { ctx.stroke(path, with: .color(Theme.panel.opacity(0.55)), lineWidth: 0.6) }
            if selection.contains(a.node.id) { selected.append(path) }
        }
        for p in selected { ctx.stroke(p, with: .color(Theme.selectionOutline), lineWidth: 1.5) }

        let r = geo.inner - 2
        let disc = Path(ellipseIn: CGRect(x: geo.center.x - r, y: geo.center.y - r, width: r * 2, height: r * 2))
        ctx.fill(disc, with: .radialGradient(
            Gradient(colors: [Theme.discInner, Theme.discOuter]),
            center: geo.center, startRadius: 0, endRadius: r))
        ctx.stroke(disc, with: .color(Theme.discRing), lineWidth: 2)
    }

    @ViewBuilder
    private func centerLabel(_ geo: Geo) -> some View {
        let hovered = hoverID.flatMap { model.index[$0] }
        if let node = hovered ?? model.chartCenter, let center = model.chartCenter {
            VStack(spacing: 3) {
                Text(node.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if hovered != nil {
                    Text(formatBytes(node.size))
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                    Text(formatPercent(node.size, of: center.size))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: geo.inner * 1.6)
            .position(geo.center)
            .allowsHitTesting(false)
        }
    }
}
