import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            if model.sidebarVisible {
                SidebarView(model: model)
            }
            MainPanel(model: model)
        }
        .padding(8)
        .background(Theme.window)
        .ignoresSafeArea()
        .frame(minWidth: 1040, minHeight: 620)
        .preferredColorScheme(Theme.colorScheme)
        .tint(Theme.action)
        .background(WindowConfigurator(theme: ThemeStore.shared.current))
        .sheet(isPresented: $model.showCleanSheet) { CleanSheet(model: model) }
        .sheet(isPresented: $model.showHelp) { HelpSheet(model: model) }
        .dropDestination(for: URL.self) { urls, _ in
            guard let u = urls.first, (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { return false }
            model.show(u)
            return true
        }
    }
}

// MARK: - Hauptbereich

private struct MainPanel: View {
    @Bindable var model: AppModel
    @AppStorage("columnsWidth") private var columnsWidth: Double = 790
    @State private var dragStart: Double?

    var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model)
            Rectangle().fill(Theme.divider).frame(height: 1)
            if model.focus != nil {
                GeometryReader { proxy in
                    let width = min(max(columnsWidth, 360), proxy.size.width - 340)
                    HStack(spacing: 0) {
                        Group {
                            switch model.mainTab {
                            case .structure: ColumnsView(model: model)
                            case .largest: LargestFilesView(model: model)
                            }
                        }
                        .frame(width: width)
                        splitHandle
                        SunburstView(model: model)
                    }
                }
                PathBar(model: model)
            } else if model.isScanning {
                ScanProgress(model: model)
            } else {
                Welcome(model: model)
            }
            Rectangle().fill(Theme.divider).frame(height: 1)
            SelectionBar(model: model)
        }
        .modifier(PanelBackground())
    }

    private var splitHandle: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(width: 2)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                let start = dragStart ?? columnsWidth
                dragStart = start
                columnsWidth = start + value.translation.width
            }.onEnded { _ in dragStart = nil })
    }
}

private struct TopBar: View {
    @Bindable var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        let _ = model.revision
        HStack(spacing: 12) {
            if !model.sidebarVisible {
                Color.clear.frame(width: 74, height: 1)
                CircleIconButton(symbol: "sidebar.left", help: "Seitenleiste einblenden") {
                    model.sidebarVisible = true
                }
            }
            search
            segments
            Spacer(minLength: 0)
            ThemePicker()
            CircleIconButton(symbol: "bubble.left", help: "Rückmeldung per E-Mail schreiben") {
                if let url = URL(string: "mailto:?subject=DiskAnalyzer%20R%C3%BCckmeldung") {
                    NSWorkspace.shared.open(url)
                }
            }
            CircleIconButton(symbol: "questionmark", help: "Hilfe") { model.showHelp = true }
        }
        .padding(.horizontal, 10)
        .frame(height: 62)
        .background(WindowDragArea())
        .overlay {
            if let root = model.root {
                HStack(spacing: 12) {
                    Text(root.name)
                    Text("Größe: \(formatBytes(root.size))")
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .monospacedDigit()
                .allowsHitTesting(false)
            }
        }
        .onChange(of: model.searchVisible) { _, visible in
            searchFocused = visible
            if !visible { model.searchText = "" }
        }
        .onChange(of: model.searchText) { _, text in
            if !text.isEmpty, model.focus != nil { model.mainTab = .largest }
        }
    }

    @ViewBuilder
    private var search: some View {
        if model.searchVisible {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12))
                TextField("Dateien suchen", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($searchFocused)
                    .onExitCommand { model.searchVisible = false }
                Button { model.searchVisible = false } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .help("Suche schließen")
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
            .frame(width: 210, height: 34)
            .background(Theme.circleButton, in: Capsule())
            .onAppear { searchFocused = true }
        } else {
            CircleIconButton(symbol: "magnifyingglass", help: "Dateien suchen (⌘F)") {
                model.searchVisible = true
            }
        }
    }

    private var segments: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { tab in
                Button { model.mainTab = tab } label: {
                    Text(tab.label)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 20)
                        .frame(height: 30)
                        .background(model.mainTab == tab ? Theme.segmentActive : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.segmentTrack, in: Capsule())
    }
}

private struct PathBar: View {
    let model: AppModel

    var body: some View {
        let _ = model.revision
        var chain: [FileNode] = []
        var p: FileNode? = model.cursor
        while let n = p {
            chain.insert(n, at: 0)
            p = n.parent
        }
        return HStack(spacing: 12) {
            ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    ForEach(Array(chain.enumerated()), id: \.element.id) { i, n in
                        if i > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Button { model.activate(n) } label: {
                            HStack(spacing: 4) {
                                Image(nsImage: IconCache.icon(for: n.url))
                                    .resizable()
                                    .frame(width: 15, height: 15)
                                Text(n.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(n.id)
                    }
                }
                .padding(.leading, 12)
            }
            .scrollIndicators(.never)
            .onChange(of: chain.last?.id) { _, id in
                if let id { proxy.scrollTo(id, anchor: .trailing) }
            }
            }
            status
        }
        .padding(.trailing, 12)
        .frame(height: 30)
        .background(Theme.pathBar)
    }

    private var status: some View {
        HStack(spacing: 10) {
            if model.skippedFolders > 0 {
                Text("\(model.skippedFolders) Ordner ohne Zugriff")
                    .foregroundStyle(.orange)
                    .help("Für vollständige Ergebnisse: Systemeinstellungen → Datenschutz & Sicherheit → Festplattenvollzugriff")
            }
            if model.freedBytes > 0 {
                Text("\(formatBytes(model.freedBytes)) freigegeben")
                    .foregroundStyle(.green)
            }
            if model.volumeTotal > 0 {
                Text("Frei: \(formatBytes(model.volumeFree)) von \(formatBytes(model.volumeTotal))")
                    .foregroundStyle(Theme.textTertiary)
                    .help("\(model.scannedItems.formatted()) Objekte analysiert")
            }
        }
        .font(.system(size: 11).monospacedDigit())
        .lineLimit(1)
        .fixedSize()
    }
}

private struct SelectionBar: View {
    let model: AppModel

    var body: some View {
        let _ = model.revision
        let nodes = model.pruned(model.selectedNodes)
        let parts = formatBytes(nodes.reduce(Int64(0)) { $0 + $1.size })
            .split(whereSeparator: \.isWhitespace).map(String.init)
        HStack(spacing: 8) {
            stat(value: parts.first ?? "0", unit: parts.dropFirst().first ?? "KB", caption: "ausgewählt")
            Rectangle().fill(Theme.textTertiary.opacity(0.45)).frame(width: 1, height: 44).padding(.horizontal, 4)
            stat(value: nodes.count.formatted(), unit: nodes.count == 1 ? "Objekt" : "Objekte", caption: "ausgewählt")
            Spacer()
            removeButton(nodes)
        }
        .padding(.leading, 24)
        .padding(.trailing, 18)
        .frame(height: 82)
    }

    private func stat(value: String, unit: String, caption: String) -> some View {
        HStack(spacing: 7) {
            Text(value)
                .font(.system(size: 30, weight: .regular).monospacedDigit())
                .foregroundStyle(Theme.text)
            VStack(alignment: .leading, spacing: 0) {
                Text(unit).fontWeight(.medium)
                Text(caption)
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private func removeButton(_ nodes: [FileNode]) -> some View {
        HStack(spacing: 0) {
            Button { model.confirmAndDelete(nodes, permanent: false) } label: {
                Text("Entfernen")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.leading, 24)
                    .padding(.trailing, 12)
                    .frame(height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("In den Papierkorb legen")
            Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1, height: 24)
            Menu {
                Button("In den Papierkorb legen …") { model.confirmAndDelete(nodes, permanent: false) }
                Button("Endgültig löschen …", role: .destructive) { model.confirmAndDelete(nodes, permanent: true) }
                Divider()
                Button("Im Finder zeigen") { model.revealInFinder(nodes) }
                Button("Auswahl aufheben") { model.selection = [] }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(.white)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(height: 48)
            .help("Weitere Aktionen")
        }
        .background(Theme.action, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(nodes.isEmpty ? 0.4 : 1)
        .disabled(nodes.isEmpty)
    }
}

private struct ScanProgress: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Analysiere \(model.lastURL?.lastPathComponent ?? "") …")
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
            Text("\(model.scannedItems.formatted()) Objekte")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            Button("Abbrechen") { model.cancelScan() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct Welcome: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 58))
                .foregroundStyle(Theme.discRing)
            Text("Ordner oder Datenträger analysieren")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.text)
            Text("Wähle links einen Speicherort oder ziehe einen Ordner in dieses Fenster.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Button("Ordner auswählen …") { model.chooseFolder() }
                .keyboardShortcut(.defaultAction)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Mehr aufräumen

private struct CleanSheet: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Mehr aufräumen")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer()
                HStack(spacing: 0) {
                    ForEach(CleanTab.allCases) { tab in
                        Button { model.cleanTab = tab } label: {
                            Text(tab.label)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.text)
                                .padding(.horizontal, 16)
                                .frame(height: 28)
                                .background(model.cleanTab == tab ? Theme.segmentActive : .clear, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Theme.segmentTrack, in: Capsule())
                Spacer()
                Button("Fertig") { model.showCleanSheet = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Rectangle().fill(Theme.divider).frame(height: 1)
            Group {
                switch model.cleanTab {
                case .cleanup: CleanupPanel(model: model)
                case .duplicates: DuplicatesPanel(model: model)
                case .types: TypesPanel(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            SelectionFooter(model: model)
        }
        .frame(width: 860, height: 600)
        .background(Theme.panel)
        .preferredColorScheme(Theme.colorScheme)
    }
}

// MARK: - Hilfe

private struct HelpSheet: View {
    let model: AppModel

    private let topics: [(String, String)] = [
        ("Analysieren", "Links einen Speicherort anklicken, einen Ordner auswählen oder einen Ordner ins Fenster ziehen. Ein Haken zeigt: Dieser Ort ist schon analysiert und öffnet sofort."),
        ("Ordnerstruktur", "Ein Klick öffnet einen Ordner in der nächsten Spalte. Rechts zeigt das Diagramm denselben Ort; ein Klick auf einen Ring springt dorthin, ein Klick in die Mitte eine Ebene hoch."),
        ("Kleine und versteckte Elemente", "Jede Spalte zeigt die zehn größten sichtbaren Objekte ab 100 KB. Alles andere liegt in den Sammelzeilen und lässt sich dort aufklappen."),
        ("Größte Dateien", "Listet die größten Dateien im aktuellen Ordner, mit Filtern nach Typ und Alter. Die Suche über die Lupe zeigt ihre Treffer hier."),
        ("Farbschema", "Die Palette oben rechts wechselt zwischen sechs Farbschemata. Die Wahl bleibt beim nächsten Start erhalten."),
        ("Entfernen", "Objekte anhaken und unten rechts „Entfernen“ wählen. Das legt sie nach einer Rückfrage in den Papierkorb. Der Pfeil daneben bietet auch endgültiges Löschen."),
        ("Mehr aufräumen", "Unten in der Seitenleiste: Aufräum-Vorschläge, inhaltliche Duplikatsuche und die Aufteilung nach Dateitypen."),
    ]
    private let keys: [(String, String)] = [
        ("⌘O", "Ordner auswählen"), ("⌘R", "Neu scannen"), ("⌘F", "Suchen"),
        ("⌘[  ⌘]", "Zurück / Vor"), ("⌘↑", "Eine Ebene hoch"),
        ("↑ ↓ ← →", "In den Spalten bewegen"), ("Leertaste", "An- oder abhaken"),
        ("⌘⌫", "Auswahl entfernen"), ("⌘-Klick im Diagramm", "An- oder abhaken"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Hilfe").font(.system(size: 15, weight: .medium))
                Spacer()
                Button("Fertig") { model.showHelp = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Rectangle().fill(Theme.divider).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(topics, id: \.0) { t in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t.0).font(.system(size: 13, weight: .semibold))
                            Text(t.1)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("Tastenkürzel").font(.system(size: 13, weight: .semibold)).padding(.top, 4)
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 5) {
                        ForEach(keys, id: \.0) { k in
                            GridRow {
                                Text(k.0).font(.system(size: 12.5).monospacedDigit())
                                Text(k.1).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(Theme.text)
        .frame(width: 520, height: 560)
        .background(Theme.panel)
        .preferredColorScheme(Theme.colorScheme)
    }
}
