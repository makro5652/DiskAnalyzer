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
            Button("Im Diagramm zeigen") { model.showInChart(node) }
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

// MARK: - Baum

struct FileListView: View {
    @Bindable var model: AppModel

    var body: some View {
        let _ = model.revision
        let rows = model.visibleRows()
        let total = model.focus?.size ?? 0

        VStack(spacing: 0) {
            HStack {
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("Anteil").frame(width: 126, alignment: .trailing)
                Text("Größe").frame(width: 74, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            Divider()

            ScrollViewReader { proxy in
                List(rows, selection: $model.selection) { row in
                    FileRowView(model: model, row: row, total: total)
                        .contextMenu { NodeActions(model: model, node: row.node) }
                }
                .listStyle(.inset)
                .onChange(of: model.selection) { _, sel in
                    if sel.count == 1, let id = sel.first { proxy.scrollTo(id) }
                }
            }
        }
    }
}

private struct FileRowView: View {
    let model: AppModel
    let row: FileRow
    let total: Int64

    var body: some View {
        let node = row.node
        let expandable = node.isDirectory && !node.children.isEmpty
        HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(row.depth) * 14, height: 1)
            Group {
                if expandable {
                    Image(systemName: model.expanded.contains(node.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                        .onTapGesture { model.toggleExpanded(node) }
                } else {
                    Color.clear
                }
            }
            .frame(width: 12)
            Image(systemName: node.isDirectory ? "folder.fill" : node.kind.symbol)
                .foregroundStyle(node.isDirectory ? Color.accentColor : node.kind.color)
                .frame(width: 18)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            SizeBar(fraction: total > 0 ? Double(node.size) / Double(total) : 0)
            Text(formatPercent(node.size, of: total))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
            Text(formatBytes(node.size))
                .font(.system(.body).monospacedDigit())
                .frame(width: 74, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if expandable { model.drill(into: node) } else { model.open(node) }
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
