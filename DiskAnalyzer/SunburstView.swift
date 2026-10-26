import SwiftUI

struct Arc {
    let node: FileNode
    let depth: Int
    let start: Double   // Radiant, 0 = oben, im Uhrzeigersinn
    let end: Double
    let hue: Double
}

enum SunburstLayout {
    static let maxDepth = 5
    static let minAngle = 0.006

    static func compute(root: FileNode) -> [Arc] {
        guard root.size > 0 else { return [] }
        var out: [Arc] = []

        func walk(_ node: FileNode, depth: Int, start: Double, span: Double, hue: Double?) {
            guard depth <= maxDepth, node.size > 0 else { return }
            var a = start
            for (i, c) in node.children.enumerated() {
                let w = Double(c.size) / Double(node.size) * span
                if w < minAngle { break }   // Kinder sind nach Größe sortiert
                let h = hue ?? (Double(i) * 0.61803398875).truncatingRemainder(dividingBy: 1)
                out.append(Arc(node: c, depth: depth, start: a, end: a + w, hue: h))
                if c.isDirectory { walk(c, depth: depth + 1, start: a, span: w, hue: h) }
                a += w
            }
        }
        walk(root, depth: 1, start: 0, span: 2 * .pi, hue: nil)
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
        outer = max(10, min(size.width, size.height) / 2 - 6)
        inner = outer * 0.2
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
    }

    var body: some View {
        GeometryReader { proxy in
            let geo = Geo(size: proxy.size)
            ZStack {
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
                        // Klick auf Ordner: hineinspringen. Cmd/Shift-Klick oder Datei: auswählen.
                        if n.isDirectory, !n.children.isEmpty, !additive {
                            model.drill(into: n)
                        } else {
                            model.select(n, additive: additive)
                        }
                    case .none: if !additive { model.selection = [] }
                    }
                }
            )
            .overlay(alignment: .topLeading) {
                Picker("Farbe", selection: $model.colorMode) {
                    ForEach(ChartColorMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Farbgebung: nach Ordnern oder nach Dateityp")
                .padding(8)
            }
            .overlay(alignment: .bottomLeading) {
                if model.colorMode == .kind { legend }
            }
        }
        .onChange(of: LayoutKey(id: model.focus?.id, revision: model.revision), initial: true) {
            arcs = model.focus.map(SunburstLayout.compute) ?? []
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(FileKind.allCases) { k in
                HStack(spacing: 5) {
                    Circle().fill(k.color).frame(width: 8, height: 8)
                    Text(k.label).font(.caption2)
                }
            }
            HStack(spacing: 5) {
                Circle().fill(Color(hue: 0.6, saturation: 0.15, brightness: 0.55)).frame(width: 8, height: 8)
                Text("Ordner").font(.caption2)
            }
        }
        .padding(8)
        .allowsHitTesting(false)
    }

    private func color(_ a: Arc, hovered: Bool) -> Color {
        let n = a.node
        let b = max(0.5, 0.95 - 0.07 * Double(a.depth - 1)) + (hovered ? 0.08 : 0)
        if model.colorMode == .kind {
            if n.isDirectory { return Color(hue: 0.6, saturation: 0.15, brightness: min(1, b - 0.35)) }
            return Color(hue: n.kind.hue, saturation: n.kind.saturation, brightness: min(1, n.kind == .other ? b - 0.3 : b))
        }
        return Color(hue: a.hue, saturation: n.isDirectory ? 0.55 : 0.28, brightness: min(1, b))
    }

    private func draw(_ ctx: GraphicsContext, _ geo: Geo) {
        let bg = Color(nsColor: .windowBackgroundColor)
        let selection = model.selection
        var selected: [Path] = []
        for a in arcs {
            let path = geo.segment(depth: a.depth, start: a.start, end: a.end)
            ctx.fill(path, with: .color(color(a, hovered: a.node.id == hoverID)))
            ctx.stroke(path, with: .color(bg), lineWidth: 1.2)
            if selection.contains(a.node.id) { selected.append(path) }
        }
        for p in selected { ctx.stroke(p, with: .color(.primary), lineWidth: 2.5) }
        let hole = Path(ellipseIn: CGRect(
            x: geo.center.x - geo.inner + 3, y: geo.center.y - geo.inner + 3,
            width: geo.inner * 2 - 6, height: geo.inner * 2 - 6))
        ctx.fill(hole, with: .color(.secondary.opacity(0.12)))
    }

    @ViewBuilder
    private func centerLabel(_ geo: Geo) -> some View {
        let hovered = hoverID.flatMap { model.index[$0] }
        let node = hovered ?? model.focus
        if let node, let focus = model.focus {
            VStack(spacing: 2) {
                Text(node.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(formatBytes(node.size))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if hovered != nil {
                    Text(formatPercent(node.size, of: focus.size))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else if focus.parent != nil {
                    Text("Klick: hoch")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: geo.inner * 1.6)
            .position(geo.center)
            .allowsHitTesting(false)
        }
    }
}
