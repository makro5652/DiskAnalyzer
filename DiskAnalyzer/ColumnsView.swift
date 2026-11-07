import SwiftUI

// MARK: - Ordnerstruktur (Spalten)

struct ColumnsView: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool
    static let columnWidth: CGFloat = 256

    var body: some View {
        let _ = model.revision
        let chain = chainToFocus()
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(chain.enumerated()), id: \.element.id) { i, folder in
                        ColumnView(model: model, folder: folder,
                                   highlighted: i + 1 < chain.count ? chain[i + 1] : model.focusedFile)
                            .frame(width: Self.columnWidth)
                            .id(folder.id)
                        Rectangle().fill(Theme.divider).frame(width: 2)
                    }
                }
            }
            .onChange(of: model.focus?.id, initial: true) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .trailing) }
                focused = true
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .space]) { press in
            switch press.key {
            case .upArrow: model.moveCursor(by: -1)
            case .downArrow: model.moveCursor(by: 1)
            case .leftArrow: model.cursorOut()
            case .rightArrow: model.cursorIn()
            default: if let c = model.cursor, c.parent != nil { model.toggleChecked(c) }
            }
            return .handled
        }
    }

    private func chainToFocus() -> [FileNode] {
        var chain: [FileNode] = []
        var p = model.focus
        while let n = p {
            chain.insert(n, at: 0)
            p = n.parent
        }
        return chain
    }
}

private struct ColumnView: View {
    let model: AppModel
    let folder: FileNode
    let highlighted: FileNode?

    var body: some View {
        let content = ColumnContent(folder)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(content.shown) { row($0) }
                    if !content.small.isEmpty {
                        group(.small, title: "Kleine Elemente", size: content.smallSize, items: content.small)
                    }
                    if !content.hidden.isEmpty {
                        group(.hidden, title: "Versteckte Elemente", size: content.hiddenSize, items: content.hidden)
                    }
                    if folder.children.isEmpty {
                        Text("Dieser Ordner ist leer")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, 24)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.automatic)
            .onChange(of: highlighted?.id) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private func row(_ node: FileNode, indented: Bool = false) -> some View {
        ColumnRow(model: model, node: node, isHighlighted: node === highlighted, indented: indented)
            .id(node.id)
    }

    @ViewBuilder
    private func group(_ group: ColumnGroup, title: String, size: Int64, items: [FileNode]) -> some View {
        let open = model.expandedGroups.contains(group.key(in: folder))
        GroupRow(title: title, size: size, isOpen: open) {
            model.toggleGroup(group, in: folder)
        }
        if open {
            ForEach(items) { row($0, indented: true) }
        }
    }
}

private struct ColumnRow: View {
    let model: AppModel
    let node: FileNode
    let isHighlighted: Bool
    let indented: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            if indented { Color.clear.frame(width: 10, height: 1) }
            CheckBox(checked: model.selection.contains(node.id),
                     covered: model.isCoveredByParent(node)) {
                model.toggleChecked(node)
            }
            Button {
                if NSApp.currentEvent?.clickCount == 2, !node.isDirectory {
                    model.open(node)
                } else {
                    model.activate(node)
                }
            } label: {
                HStack(spacing: 7) {
                    Image(nsImage: IconCache.icon(for: node.url))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 20, height: 20)
                    Text(node.name)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(formatBytes(node.size))
                        .font(.system(size: 12.5).monospacedDigit())
                        .foregroundStyle(Theme.sizeColor(node.size))
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 3)
        .padding(.trailing, 9)
        .frame(height: 32)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHighlighted ? Theme.rowSelection : hovering ? Theme.rowHover : .clear)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { NodeActions(model: model, node: node) }
        .help(node.url.path)
    }
}

private struct GroupRow: View {
    let title: String
    let size: Int64
    let isOpen: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 14)
                Circle()
                    .fill(Theme.textTertiary)
                    .frame(width: 10, height: 10)
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(formatBytes(size))
                    .font(.system(size: 12).monospacedDigit())
                    .fixedSize()
            }
            .foregroundStyle(Theme.textTertiary)
            .padding(.leading, 4)
            .padding(.trailing, 9)
            .frame(height: 26)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? Theme.rowHover : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Größte Dateien

struct LargestFilesView: View {
    @Bindable var model: AppModel

    var body: some View {
        let _ = model.revision
        let result = model.filteredFiles()
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                FilterMenu(title: model.kindFilter?.label ?? "Alle Typen") {
                    Button("Alle Typen") { model.kindFilter = nil }
                    Divider()
                    ForEach(FileKind.allCases) { k in
                        Button { model.kindFilter = k } label: { Label(k.label, systemImage: k.symbol) }
                    }
                }
                FilterMenu(title: model.ageFilter.label) {
                    ForEach(AgeFilter.allCases) { a in Button(a.label) { model.ageFilter = a } }
                }
                if model.kindFilter != nil || model.ageFilter != .all || !model.searchText.isEmpty {
                    Button("Zurücksetzen") {
                        model.kindFilter = nil
                        model.ageFilter = .all
                        model.searchText = ""
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("\(result.items.count)\(result.truncated ? "+" : "") Dateien"
                     + (model.focus !== model.root ? " in „\(model.focus?.name ?? "")“" : ""))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            Rectangle().fill(Theme.divider).frame(height: 1)

            if result.items.isEmpty {
                ContentUnavailableView("Keine Dateien", systemImage: "doc.questionmark",
                                       description: Text("Mit den aktuellen Filtern wurde nichts gefunden."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(result.items) { LargestRow(model: model, node: $0) }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

private struct FilterMenu<Items: View>: View {
    let title: String
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu(content: items) {
            Text(title).font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .tint(Theme.text)
        .fixedSize()
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Theme.segmentTrack, in: Capsule())
    }
}

private struct LargestRow: View {
    let model: AppModel
    let node: FileNode
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            CheckBox(checked: model.selection.contains(node.id),
                     covered: model.isCoveredByParent(node)) {
                model.toggleChecked(node)
            }
            Button {
                if NSApp.currentEvent?.clickCount == 2 { model.open(node) } else { model.focusedFile = node }
            } label: {
                HStack(spacing: 7) {
                    Image(nsImage: IconCache.icon(for: node.url))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.name)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(node.folderPath)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Spacer(minLength: 8)
                    Text(formatDate(node.modified))
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize()
                    Text(formatBytes(node.size))
                        .font(.system(size: 12.5).monospacedDigit())
                        .foregroundStyle(Theme.sizeColor(node.size))
                        .frame(width: 70, alignment: .trailing)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 3)
        .padding(.trailing, 9)
        .frame(height: 42)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(model.focusedFile === node ? Theme.rowSelection : hovering ? Theme.rowHover : .clear)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { NodeActions(model: model, node: node) }
    }
}
