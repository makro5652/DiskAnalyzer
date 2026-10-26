import SwiftUI

// MARK: - Dateien (flach, filterbar)

struct FilesPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        let _ = model.revision
        let result = model.filteredFiles()
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Menu {
                    Button("Alle Typen") { model.kindFilter = nil }
                    Divider()
                    ForEach(FileKind.allCases) { k in
                        Button { model.kindFilter = k } label: { Label(k.label, systemImage: k.symbol) }
                    }
                } label: {
                    Text(model.kindFilter?.label ?? "Alle Typen")
                }
                .fixedSize()
                Menu {
                    ForEach(AgeFilter.allCases) { a in Button(a.label) { model.ageFilter = a } }
                } label: {
                    Text(model.ageFilter.label)
                }
                .fixedSize()
                Spacer()
                if model.kindFilter != nil || model.ageFilter != .all || !model.searchText.isEmpty {
                    Button("Zurücksetzen") {
                        model.kindFilter = nil
                        model.ageFilter = .all
                        model.searchText = ""
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            HStack {
                Text("\(result.items.count)\(result.truncated ? "+" : "") Dateien · größte zuerst"
                     + (model.focus !== model.root ? " · in „\(model.focus?.name ?? "")“" : ""))
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            Divider()

            if result.items.isEmpty {
                ContentUnavailableView("Keine Dateien", systemImage: "doc.questionmark",
                                       description: Text("Mit den aktuellen Filtern wurde nichts gefunden."))
            } else {
                List(result.items, selection: $model.selection) { f in
                    HStack(spacing: 8) {
                        Image(systemName: f.kind.symbol)
                            .foregroundStyle(f.kind.color)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.name).lineLimit(1).truncationMode(.middle)
                            Text(f.folderPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                        Spacer()
                        Text(formatDate(f.modified))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(formatBytes(f.size))
                            .monospacedDigit()
                            .frame(width: 74, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.open(f) }
                    .contextMenu { NodeActions(model: model, node: f) }
                }
                .listStyle(.inset)
            }
        }
    }
}

// MARK: - Typen

struct TypesPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        let total = model.root?.size ?? 0
        let stats = FileKind.allCases
            .compactMap { k in model.snapshot.kindStats[k].map { (k, $0) } }
            .sorted { $0.1.size > $1.1.size }
        List(stats, id: \.0) { k, s in
            HStack(spacing: 8) {
                Image(systemName: k.symbol)
                    .foregroundStyle(k.color)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(k.label)
                    Text("\(s.count.formatted()) Dateien")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                SizeBar(fraction: total > 0 ? Double(s.size) / Double(total) : 0, color: k.color)
                Text(formatPercent(s.size, of: total))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
                Text(formatBytes(s.size))
                    .monospacedDigit()
                    .frame(width: 74, alignment: .trailing)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onTapGesture {
                model.kindFilter = k
                model.tab = .files
            }
            .help("Klicken, um alle Dateien dieses Typs zu sehen")
        }
        .listStyle(.inset)
    }
}

// MARK: - Duplikate

struct DuplicatesPanel: View {
    @Bindable var model: AppModel
    private let sizes: [(String, Int64)] = [
        ("ab 100 KB", 100_000), ("ab 1 MB", 1_000_000), ("ab 10 MB", 10_000_000), ("ab 100 MB", 100_000_000),
    ]

    var body: some View {
        let wasted = model.dupGroups.reduce(Int64(0)) { $0 + $1.wasted }
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Menu(sizes.first { $0.1 == model.dupMinSize }?.0 ?? "") {
                    ForEach(sizes, id: \.1) { s in Button(s.0) { model.dupMinSize = s.1 } }
                }
                .fixedSize()
                .disabled(model.dupRunning)
                if model.dupRunning {
                    Button("Abbrechen") { model.cancelDuplicates() }
                } else {
                    Button(model.dupDone ? "Erneut suchen" : "Duplikate suchen") { model.findDuplicates() }
                }
                Spacer()
                if model.dupDone, !model.dupGroups.isEmpty {
                    Button("Kopien markieren (älteste behalten)") { model.selectDuplicatesKeepingOldest() }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if model.dupRunning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.dupProgress).lineLimit(1).truncationMode(.middle)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            } else if model.dupDone {
                HStack {
                    Text("\(model.dupGroups.count) Gruppen · \(formatBytes(wasted)) durch Kopien belegt")
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
            Divider()

            if model.dupDone, model.dupGroups.isEmpty {
                ContentUnavailableView("Keine Duplikate", systemImage: "checkmark.circle",
                                       description: Text("In diesem Scan gibt es keine identischen Dateien in dieser Größe."))
            } else if !model.dupDone, !model.dupRunning {
                ContentUnavailableView("Identische Dateien finden", systemImage: "doc.on.doc",
                                       description: Text("Vergleicht Dateien inhaltlich (SHA-256). Hardlinks werden nicht als Duplikate gezählt."))
            } else {
                List(selection: $model.selection) {
                    ForEach(model.dupGroups.prefix(300)) { g in
                        Section {
                            ForEach(g.nodes) { n in
                                HStack(spacing: 8) {
                                    Image(systemName: n.kind.symbol)
                                        .foregroundStyle(n.kind.color)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(n.name).lineLimit(1).truncationMode(.middle)
                                        Text(n.folderPath)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.head)
                                    }
                                    Spacer()
                                    Text(formatDate(n.modified))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { model.open(n) }
                                .contextMenu {
                                    NodeActions(model: model, node: n)
                                    Divider()
                                    Button("Nur diese Kopie behalten (andere markieren)") {
                                        model.keepOnly(n, in: g)
                                    }
                                }
                            }
                        } header: {
                            Text("\(g.nodes[0].name) · \(formatBytes(g.size)) × \(g.nodes.count) — \(formatBytes(g.wasted)) Verschwendung")
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

// MARK: - Aufräumen

struct CleanupPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        let items = model.snapshot.cleanup
        let total = items.reduce(Int64(0)) { $0 + $1.node.size }
        VStack(spacing: 0) {
            HStack {
                Text(items.isEmpty ? "Bekannte Platzfresser" : "\(items.count) Kandidaten · bis zu \(formatBytes(total)) frei")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !items.isEmpty {
                    Button("Alle markieren") { model.selection = Set(items.map(\.id)) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()

            if items.isEmpty {
                ContentUnavailableView("Nichts Bekanntes gefunden", systemImage: "sparkles",
                                       description: Text("Gesucht wird nach Caches, Xcode-Daten, node_modules, iPhone-Backups, Papierkorb und alten Installationsabbildern. Tipp: Analysiere deinen Benutzerordner."))
            } else {
                List(items, selection: $model.selection) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.node.isDirectory ? "folder.fill" : item.node.kind.symbol)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.node.name).lineLimit(1).truncationMode(.middle)
                            Text(item.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(item.node.folderPath)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                        Spacer()
                        Text(formatBytes(item.node.size))
                            .monospacedDigit()
                            .frame(width: 74, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.showInChart(item.node) }
                    .contextMenu { NodeActions(model: model, node: item.node) }
                }
                .listStyle(.inset)
            }
        }
    }
}
