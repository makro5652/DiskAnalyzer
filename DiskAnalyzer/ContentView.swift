import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.focus != nil {
                breadcrumb
                Divider()
                HSplitView {
                    SunburstView(model: model)
                        .frame(minWidth: 340, minHeight: 340)
                    rightPane
                        .frame(minWidth: 440)
                }
            } else if model.isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Analysiere … \(model.scannedItems.formatted()) Objekte")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button("Abbrechen") { model.cancelScan() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary)
                    Text("Ordner oder Datenträger analysieren")
                        .font(.title3)
                    Text("Wähle einen Speicherort oder ziehe einen Ordner in dieses Fenster.")
                        .foregroundStyle(.secondary)
                    Button("Ordner wählen …") { model.chooseFolder() }
                        .keyboardShortcut(.defaultAction)
                    HStack {
                        ForEach(model.quickLocations().prefix(4), id: \.1) { loc in
                            Button(loc.0) { model.scan(loc.1) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 900, minHeight: 520)
        .toolbar { toolbar }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Dateien suchen")
        .onChange(of: model.searchText) { _, text in
            if !text.isEmpty, model.focus != nil { model.tab = .files }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let u = urls.first, (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { return false }
            model.scan(u)
            return true
        }
    }

    // MARK: Teile

    private var rightPane: some View {
        VStack(spacing: 0) {
            Picker("Ansicht", selection: $model.tab) {
                ForEach(PanelTab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()
            switch model.tab {
            case .tree: FileListView(model: model)
            case .files: FilesPanel(model: model)
            case .types: TypesPanel(model: model)
            case .duplicates: DuplicatesPanel(model: model)
            case .cleanup: CleanupPanel(model: model)
            }
            SelectionFooter(model: model)
        }
    }

    private var breadcrumb: some View {
        let _ = model.revision
        var chain: [FileNode] = []
        var p = model.focus
        while let n = p { chain.insert(n, at: 0); p = n.parent }
        return HStack(spacing: 0) {
            HStack(spacing: 2) {
                Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!model.canGoBack)
                    .help("Zurück (⌘[)")
                Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!model.canGoForward)
                    .help("Vor (⌘])")
                Button { model.goUp() } label: { Image(systemName: "arrow.up") }
                    .disabled(model.focus?.parent == nil)
                    .help("Eine Ebene hoch")
            }
            .buttonStyle(.borderless)
            .padding(.leading, 10)
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(chain.enumerated()), id: \.element.id) { i, n in
                    if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    Button(n.name) { model.navigate(to: n) }
                    .buttonStyle(.plain)
                    .fontWeight(n === model.focus ? .semibold : .regular)
                }
            }
            .padding(.horizontal, 12)
            }
        }
        .frame(height: 30)
    }

    private var statusBar: some View {
        let _ = model.revision
        return HStack(spacing: 12) {
            if model.isScanning {
                ProgressView().controlSize(.small)
                Text("Analysiere … \(model.scannedItems.formatted()) Objekte")
            } else if let root = model.root {
                Text("\(root.url.path): \(formatBytes(root.size)) · \(model.scannedItems.formatted()) Objekte")
                if model.skippedFolders > 0 {
                    Text("\(model.skippedFolders) Ordner ohne Zugriff")
                        .foregroundStyle(.orange)
                }
                if model.freedBytes > 0 {
                    Text("\(formatBytes(model.freedBytes)) freigegeben")
                        .foregroundStyle(.green)
                }
            }
            Spacer()
            if model.volumeTotal > 0, model.root != nil {
                ProgressView(value: Double(model.volumeTotal - model.volumeFree), total: Double(model.volumeTotal))
                    .frame(width: 70)
                Text("Frei: \(formatBytes(model.volumeFree)) von \(formatBytes(model.volumeTotal))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 24)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Menu {
                ForEach(model.quickLocations(), id: \.1) { loc in
                    Button(loc.0) { model.scan(loc.1) }
                }
                if !model.recents.isEmpty {
                    Divider()
                    Section("Zuletzt") {
                        ForEach(model.recents, id: \.self) { path in
                            Button((path as NSString).abbreviatingWithTildeInPath) {
                                model.scan(URL(fileURLWithPath: path))
                            }
                        }
                    }
                }
            } label: {
                Label("Ordner wählen", systemImage: "folder.badge.plus")
            } primaryAction: {
                model.chooseFolder()
            }
            .keyboardShortcut("o")
            Button { model.rescan() } label: {
                Label("Neu scannen", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r")
            .disabled(model.lastURL == nil || model.isScanning)
            Button { model.goUp() } label: {
                Label("Eine Ebene hoch", systemImage: "arrow.up")
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(model.focus?.parent == nil)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            let sel = model.selectedNodes
            Button { model.revealInFinder(sel) } label: {
                Label("Im Finder zeigen", systemImage: "magnifyingglass")
            }
            .help("Im Finder zeigen")
            .disabled(sel.isEmpty)
            Button { if let n = model.selectedNode { model.open(n) } } label: {
                Label("Öffnen", systemImage: "arrow.up.forward.app")
            }
            .help("Öffnen")
            .disabled(model.selectedNode == nil)
            Button { model.confirmAndDelete(sel) } label: {
                Label("Löschen", systemImage: "trash")
            }
            .help("Löschen …")
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(sel.isEmpty)
        }
    }
}
