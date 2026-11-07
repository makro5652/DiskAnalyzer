import SwiftUI

struct NodeActions: View {
    let model: AppModel
    let node: FileNode

    var body: some View {
        let targets = model.targets(for: node)
        let multi = targets.count > 1
        Button(multi ? "\(targets.count) Objekte im Finder zeigen" : "Im Finder zeigen") {
            model.revealInFinder(targets)
        }
        if !multi {
            Button("Öffnen") { model.open(node) }
            Button("In Spalten und Diagramm zeigen") { model.showInChart(node) }
            Button("Pfad kopieren") { model.copyPath(node) }
        }
        Divider()
        Button(multi ? "\(targets.count) Objekte löschen …" : "Löschen …", role: .destructive) {
            model.confirmAndDelete(targets)
        }
    }
}

/// Auswahl-Zusammenfassung mit Sammelaktionen, unter allen Listen sichtbar.
struct SelectionFooter: View {
    let model: AppModel

    var body: some View {
        let nodes = model.pruned(model.selectedNodes)
        if !nodes.isEmpty {
            Divider()
            HStack {
                Text("\(nodes.count) ausgewählt · \(formatBytes(nodes.reduce(Int64(0)) { $0 + $1.size }))")
                    .font(.callout.monospacedDigit())
                Spacer()
                Button("Aufheben") { model.selection = [] }
                Button("Im Finder zeigen") { model.revealInFinder(nodes) }
                Button("Löschen …", role: .destructive) { model.confirmAndDelete(nodes) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}

struct SizeBar: View {
    let fraction: Double
    var color: Color = .accentColor

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.quaternary)
            Capsule().fill(color.opacity(0.7)).frame(width: 56 * CGFloat(min(1, max(0, fraction))))
        }
        .frame(width: 56, height: 5)
    }
}
