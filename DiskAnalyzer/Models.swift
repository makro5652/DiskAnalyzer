import AppKit
import Foundation
import Observation
import SwiftUI

// MARK: - Dateitypen

enum FileKind: Int, CaseIterable, Identifiable {
    case image, video, audio, document, archive, code, app, other

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .image: "Bilder"
        case .video: "Videos"
        case .audio: "Audio"
        case .document: "Dokumente"
        case .archive: "Archive & Images"
        case .code: "Code & Daten"
        case .app: "Programme"
        case .other: "Sonstige"
        }
    }

    var symbol: String {
        switch self {
        case .image: "photo"
        case .video: "film"
        case .audio: "music.note"
        case .document: "doc.text"
        case .archive: "archivebox"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .app: "app.dashed"
        case .other: "doc"
        }
    }

    var hue: Double {
        switch self {
        case .image: 0.55
        case .video: 0.98
        case .audio: 0.78
        case .document: 0.09
        case .archive: 0.15
        case .code: 0.38
        case .app: 0.47
        case .other: 0
        }
    }

    var saturation: Double { self == .other ? 0 : 0.58 }

    var color: Color { Color(hue: hue, saturation: saturation, brightness: self == .other ? 0.6 : 0.9) }

    private static let table: [String: FileKind] = {
        let groups: [(FileKind, String)] = [
            (.image, "jpg jpeg png gif heic heif tiff tif bmp webp raw cr2 cr3 nef arw dng svg psd ico"),
            (.video, "mp4 mov mkv avi m4v wmv flv webm mpg mpeg"),
            (.audio, "mp3 m4a wav aac flac aiff ogg wma"),
            (.document, "pdf doc docx xls xlsx ppt pptx pages numbers key txt rtf md csv odt ods odp epub"),
            (.archive, "zip rar 7z tar gz tgz bz2 xz dmg iso pkg xip"),
            (.code, "swift m h c cpp js ts py java rb go rs json html css xml sh yml yaml"),
        ]
        var d: [String: FileKind] = [:]
        for (k, exts) in groups { for e in exts.split(separator: " ") { d[String(e)] = k } }
        return d
    }()

    static func of(ext: String) -> FileKind { table[ext] ?? .other }
}

// MARK: - Datenmodell

final class FileNode: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    var size: Int64
    var kind: FileKind = .other
    var modified: Date?
    var children: [FileNode] = []
    weak var parent: FileNode?

    var id: String { url.path }

    init(url: URL, isDirectory: Bool, size: Int64) {
        self.url = url
        self.name = url.path == "/" ? "/" : url.lastPathComponent
        self.isDirectory = isDirectory
        self.size = size
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    func isDescendant(of other: FileNode) -> Bool {
        var p: FileNode? = self
        while let n = p {
            if n === other { return true }
            p = n.parent
        }
        return false
    }

    var folderPath: String {
        (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }
}

extension FileNode: @unchecked Sendable {}

private let byteFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f
}()

func formatBytes(_ n: Int64) -> String { byteFormatter.string(fromByteCount: n) }

func formatPercent(_ part: Int64, of total: Int64) -> String {
    guard total > 0 else { return "–" }
    let p = Double(part) / Double(total) * 100
    return p < 0.1 ? "<0,1 %" : String(format: "%.1f %%", p).replacingOccurrences(of: ".", with: ",")
}

func formatDate(_ d: Date?) -> String {
    d.map { $0.formatted(date: .numeric, time: .omitted) } ?? "–"
}

// MARK: - Scanner

final class ScanContext: @unchecked Sendable {
    private let lock = NSLock()
    private var _items = 0
    private var _skipped = 0
    private var _cancelled = false

    var items: Int { lock.withLock { _items } }
    var skipped: Int { lock.withLock { _skipped } }
    var isCancelled: Bool { lock.withLock { _cancelled } }

    func noteItem() { lock.withLock { _items += 1 } }
    func noteSkipped() { lock.withLock { _skipped += 1 } }
    func cancel() { lock.withLock { _cancelled = true } }
}

enum DiskScanner {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        .contentModificationDateKey,
    ]

    /// Pfade, die beim Scannen von „/“ Daten doppelt zählen würden (Firmlinks) oder keine echten Dateien sind.
    private static let skipPaths: Set<String> = ["/System/Volumes", "/Volumes", "/dev"]

    static func scan(_ url: URL, context: ScanContext) -> FileNode {
        let root = FileNode(url: url, isDirectory: true, size: 0)
        fill(root, context, inBundle: false)
        return root
    }

    private static func fill(_ dir: FileNode, _ ctx: ScanContext, inBundle: Bool) {
        if ctx.isCancelled { return }
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir.url, includingPropertiesForKeys: keys, options: []
        ) else {
            ctx.noteSkipped()
            return
        }

        var kids: [FileNode] = []
        var total: Int64 = 0
        kids.reserveCapacity(urls.count)

        autoreleasepool {
            for u in urls {
                if dir.url.path == "/", skipPaths.contains(u.path) { continue }
                let v = try? u.resourceValues(forKeys: Set(keys))
                ctx.noteItem()
                if v?.isSymbolicLink == true { continue }

                let ext = u.pathExtension.lowercased()
                let child: FileNode
                if v?.isDirectory == true {
                    child = FileNode(url: u, isDirectory: true, size: 0)
                    child.parent = dir
                    fill(child, ctx, inBundle: inBundle || ext == "app")
                } else {
                    let s = v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0
                    child = FileNode(url: u, isDirectory: false, size: Int64(s))
                    child.kind = inBundle ? .app : FileKind.of(ext: ext)
                    child.parent = dir
                }
                child.modified = v?.contentModificationDate
                total += child.size
                kids.append(child)
            }
        }

        kids.sort { $0.size > $1.size }
        dir.children = kids
        dir.size = total
    }
}

// MARK: - Auswertung (Index, Typen, Aufräum-Vorschläge)

struct KindStat {
    var count = 0
    var size: Int64 = 0
}

struct CleanupItem: Identifiable {
    let node: FileNode
    let reason: String
    var id: String { node.id }
}

enum CleanupRules {
    static func reason(for n: FileNode) -> String? {
        let p = n.parent
        if n.isDirectory {
            switch n.name {
            case "node_modules": return "Node-Abhängigkeiten – mit „npm install“ jederzeit wiederherstellbar"
            case "DerivedData" where p?.name == "Xcode": return "Xcode-Build-Zwischendaten – werden beim nächsten Build neu erzeugt"
            case "Archives" where p?.name == "Xcode": return "Xcode-Archive – nur löschen, wenn du die Builds nicht mehr brauchst"
            case "iOS DeviceSupport" where p?.name == "Xcode": return "Xcode-Gerätesupport – wird beim nächsten Anschließen neu geladen"
            case "CoreSimulator" where p?.name == "Developer": return "Simulator-Daten – Geräte lassen sich neu anlegen"
            case ".Trash": return "Papierkorb"
            case "Backup" where p?.name == "MobileSync": return "iPhone-/iPad-Backups"
            default: break
            }
            if p?.name == "Caches", p?.parent?.name == "Library" {
                return "App-Cache – wird bei Bedarf neu aufgebaut"
            }
        } else {
            let ext = n.url.pathExtension.lowercased()
            if ["dmg", "iso", "pkg", "xip"].contains(ext) {
                var a = p
                for _ in 0..<6 {
                    if a?.name == "Downloads" { return "Installationsabbild im Downloads-Ordner – nach der Installation meist überflüssig" }
                    a = a?.parent
                }
            }
        }
        return nil
    }
}

struct Snapshot {
    var index: [String: FileNode] = [:]
    var files: [FileNode] = []          // nach Größe absteigend
    var kindStats: [FileKind: KindStat] = [:]
    var cleanup: [CleanupItem] = []

    static func build(_ root: FileNode) -> Snapshot {
        var s = Snapshot()
        func walk(_ n: FileNode, suggested: Bool) {
            s.index[n.id] = n
            var sug = suggested
            if !suggested, n.size > 0, let reason = CleanupRules.reason(for: n) {
                s.cleanup.append(CleanupItem(node: n, reason: reason))
                sug = true
            }
            if n.isDirectory {
                for c in n.children { walk(c, suggested: sug) }
            } else {
                s.files.append(n)
                s.kindStats[n.kind, default: KindStat()].count += 1
                s.kindStats[n.kind, default: KindStat()].size += n.size
            }
        }
        walk(root, suggested: false)
        s.files.sort { $0.size > $1.size }
        s.cleanup.sort { $0.node.size > $1.node.size }
        return s
    }
}

extension Snapshot: @unchecked Sendable {}

// MARK: - Filter & Tabs

enum PanelTab: String, CaseIterable, Identifiable {
    case tree, files, types, duplicates, cleanup
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tree: "Baum"
        case .files: "Dateien"
        case .types: "Typen"
        case .duplicates: "Duplikate"
        case .cleanup: "Aufräumen"
        }
    }
}

enum AgeFilter: String, CaseIterable, Identifiable {
    case all, d30, m6, y1, y3
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "Beliebiges Alter"
        case .d30: "Älter als 30 Tage"
        case .m6: "Älter als 6 Monate"
        case .y1: "Älter als 1 Jahr"
        case .y3: "Älter als 3 Jahre"
        }
    }
    var cutoff: Date? {
        let cal = Calendar.current
        switch self {
        case .all: return nil
        case .d30: return cal.date(byAdding: .day, value: -30, to: .now)
        case .m6: return cal.date(byAdding: .month, value: -6, to: .now)
        case .y1: return cal.date(byAdding: .year, value: -1, to: .now)
        case .y3: return cal.date(byAdding: .year, value: -3, to: .now)
        }
    }
}

enum ChartColorMode: String, CaseIterable, Identifiable {
    case folder, kind
    var id: String { rawValue }
    var label: String { self == .folder ? "Ordner" : "Typ" }
}

// MARK: - App-Modell

@MainActor @Observable
final class AppModel {
    var root: FileNode?
    var focus: FileNode?
    var selection: Set<String> = []
    var expanded: Set<String> = []
    var revision = 0
    var isScanning = false
    var scannedItems = 0
    var skippedFolders = 0
    var lastURL: URL?
    private(set) var snapshot = Snapshot()
    private(set) var backStack: [FileNode] = []
    private(set) var forwardStack: [FileNode] = []

    // Ansicht
    var tab: PanelTab = .tree
    var colorMode: ChartColorMode = .folder
    var searchText = ""
    var kindFilter: FileKind?
    var ageFilter: AgeFilter = .all

    // Datenträger / Sitzung
    var volumeTotal: Int64 = 0
    var volumeFree: Int64 = 0
    var freedBytes: Int64 = 0
    var recents: [String] = UserDefaults.standard.stringArray(forKey: "recents") ?? []

    // Duplikate
    var dupGroups: [DupGroup] = []
    var dupRunning = false
    var dupDone = false
    var dupProgress = ""
    var dupMinSize: Int64 = 1_000_000
    @ObservationIgnored private var dupContext: ScanContext?

    @ObservationIgnored private var context: ScanContext?

    var index: [String: FileNode] { snapshot.index }
    var selectedNodes: [FileNode] { selection.compactMap { index[$0] } }
    var selectedNode: FileNode? { selection.count == 1 ? selection.first.flatMap { index[$0] } : nil }

    // MARK: Scannen

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Analysieren"
        panel.message = "Wähle einen Ordner oder Datenträger zur Analyse"
        if panel.runModal() == .OK, let url = panel.url { scan(url) }
    }

    func quickLocations() -> [(String, URL)] {
        let fm = FileManager.default
        var out: [(String, URL)] = [("Benutzerordner", fm.homeDirectoryForCurrentUser)]
        for (title, dir) in [("Schreibtisch", FileManager.SearchPathDirectory.desktopDirectory),
                             ("Dokumente", .documentDirectory),
                             ("Downloads", .downloadsDirectory),
                             ("Programme", .applicationDirectory)] {
            if let u = fm.urls(for: dir, in: .userDomainMask).first ?? fm.urls(for: dir, in: .localDomainMask).first {
                out.append((title, u))
            }
        }
        out.append(("Gesamter Mac (/)", URL(fileURLWithPath: "/")))
        let vols = fm.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: [.skipHiddenVolumes]) ?? []
        for v in vols where v.path.hasPrefix("/Volumes/") {
            out.append((v.lastPathComponent, v))
        }
        return out
    }

    func cancelScan() {
        context?.cancel()
        context = nil
        isScanning = false
    }

    func rescan() {
        if let url = lastURL { scan(url) }
    }

    func scan(_ url: URL) {
        context?.cancel()
        dupContext?.cancel()
        let ctx = ScanContext()
        context = ctx
        lastURL = url
        recents = ([url.path] + recents.filter { $0 != url.path }).prefix(6).map { $0 }
        UserDefaults.standard.set(recents, forKey: "recents")
        isScanning = true
        scannedItems = 0
        skippedFolders = 0
        freedBytes = 0
        root = nil
        focus = nil
        backStack = []
        forwardStack = []
        selection = []
        expanded = []
        snapshot = Snapshot()
        dupGroups = []
        dupDone = false
        dupRunning = false
        kindFilter = nil
        revision += 1

        Task { [weak self] in
            let poller = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    self?.scannedItems = ctx.items
                    try? await Task.sleep(for: .milliseconds(120))
                }
            }
            let result = await Task.detached(priority: .userInitiated) { () -> (FileNode, Snapshot) in
                let r = DiskScanner.scan(url, context: ctx)
                return (r, ctx.isCancelled ? Snapshot() : Snapshot.build(r))
            }.value
            poller.cancel()
            guard let self, self.context === ctx, !ctx.isCancelled else { return }
            self.root = result.0
            self.focus = result.0
            self.snapshot = result.1
            self.scannedItems = ctx.items
            self.skippedFolders = ctx.skipped
            self.isScanning = false
            self.updateVolume()
            self.revision += 1
        }
    }

    private func rebuildSnapshot() {
        snapshot = root.map(Snapshot.build) ?? Snapshot()
        updateVolume()
    }

    private func updateVolume() {
        guard let url = lastURL,
              let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        else { return }
        volumeTotal = Int64(v.volumeTotalCapacity ?? 0)
        volumeFree = v.volumeAvailableCapacityForImportantUsage ?? 0
    }

    // MARK: Navigation / Auswahl

    func select(_ node: FileNode, additive: Bool = false) {
        if additive {
            if selection.contains(node.id) { selection.remove(node.id) } else { selection.insert(node.id) }
        } else {
            selection = [node.id]
        }
        var p = node.parent
        while let q = p {
            expanded.insert(q.id)
            p = q.parent
        }
    }

    /// Wechselt den im Diagramm gezeigten Ordner und merkt sich den Verlauf.
    func navigate(to node: FileNode) {
        guard node !== focus else { return }
        if let f = focus { backStack.append(f) }
        forwardStack = []
        focus = node
        revision += 1
    }

    func drill(into node: FileNode) {
        guard node.isDirectory, !node.children.isEmpty else { return }
        navigate(to: node)
    }

    func goUp() {
        guard let p = focus?.parent else { return }
        navigate(to: p)
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func goBack() {
        while let prev = backStack.popLast() {
            guard snapshot.index[prev.id] === prev else { continue }
            if let f = focus { forwardStack.append(f) }
            focus = prev
            revision += 1
            return
        }
    }

    func goForward() {
        while let next = forwardStack.popLast() {
            guard snapshot.index[next.id] === next else { continue }
            if let f = focus { backStack.append(f) }
            focus = next
            revision += 1
            return
        }
    }

    /// Zeigt ein Objekt im Diagramm und im Baum.
    func showInChart(_ node: FileNode) {
        tab = .tree
        if node.isDirectory, !node.children.isEmpty {
            navigate(to: node)
        } else {
            navigate(to: node.parent ?? node)
            select(node)
        }
    }

    func toggleExpanded(_ node: FileNode) {
        if expanded.contains(node.id) { expanded.remove(node.id) } else { expanded.insert(node.id) }
        revision += 1
    }

    func visibleRows() -> [FileRow] {
        guard let focus else { return [] }
        var out: [FileRow] = []
        func walk(_ n: FileNode, _ depth: Int) {
            for c in n.children {
                out.append(FileRow(node: c, depth: depth))
                if c.isDirectory, expanded.contains(c.id) { walk(c, depth + 1) }
            }
        }
        walk(focus, 0)
        return out
    }

    /// Dateien (größte zuerst) unter dem aktuellen Ordner, gefiltert nach Suche, Typ und Alter.
    func filteredFiles(limit: Int = 1000) -> (items: [FileNode], truncated: Bool) {
        guard let focus else { return ([], false) }
        let cutoff = ageFilter.cutoff
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let all = focus === root
        var out: [FileNode] = []
        for f in snapshot.files {
            if let k = kindFilter, f.kind != k { continue }
            if let cutoff { guard let m = f.modified, m < cutoff else { continue } }
            if !query.isEmpty, !f.name.localizedCaseInsensitiveContains(query) { continue }
            if !all, !f.isDescendant(of: focus) { continue }
            if out.count == limit { return (out, true) }
            out.append(f)
        }
        return (out, false)
    }

    // MARK: Aktionen

    func targets(for node: FileNode) -> [FileNode] {
        selection.contains(node.id) ? selectedNodes : [node]
    }

    func revealInFinder(_ nodes: [FileNode]) {
        NSWorkspace.shared.activateFileViewerSelecting(nodes.map(\.url))
    }

    func open(_ node: FileNode) {
        NSWorkspace.shared.open(node.url)
    }

    func copyPath(_ node: FileNode) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.url.path, forType: .string)
    }

    /// Entfernt Objekte, deren Elternordner ebenfalls in der Liste ist.
    func pruned(_ nodes: [FileNode]) -> [FileNode] {
        let ids = Set(nodes.map { ObjectIdentifier($0) })
        return nodes.filter { n in
            var p = n.parent
            while let q = p {
                if ids.contains(ObjectIdentifier(q)) { return false }
                p = q.parent
            }
            return true
        }
    }

    func confirmAndDelete(_ nodes: [FileNode]) {
        let top = pruned(nodes)
        guard !top.isEmpty else { return }
        let total = top.reduce(Int64(0)) { $0 + $1.size }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = top.count == 1 ? "„\(top[0].name)“ löschen?" : "\(top.count) Objekte löschen?"
        alert.informativeText = top.count == 1
            ? "\(formatBytes(total)) · \(top[0].url.path)"
            : "Zusammen \(formatBytes(total))"
        alert.addButton(withTitle: "In den Papierkorb")
        alert.addButton(withTitle: "Endgültig löschen")
        alert.addButton(withTitle: "Abbrechen")
        alert.buttons[1].hasDestructiveAction = true

        let permanent: Bool
        switch alert.runModal() {
        case .alertFirstButtonReturn: permanent = false
        case .alertSecondButtonReturn: permanent = true
        default: return
        }

        var removed: [FileNode] = []
        var errors: [String] = []
        for n in top {
            do {
                if permanent {
                    try FileManager.default.removeItem(at: n.url)
                } else {
                    try FileManager.default.trashItem(at: n.url, resultingItemURL: nil)
                }
                removed.append(n)
            } catch {
                errors.append("\(n.name): \(error.localizedDescription)")
            }
        }
        if !removed.isEmpty { remove(removed) }
        if !errors.isEmpty {
            let a = NSAlert()
            a.alertStyle = .warning
            a.messageText = "\(errors.count) Objekt(e) konnten nicht gelöscht werden"
            a.informativeText = errors.prefix(5).joined(separator: "\n")
            a.runModal()
        }
    }

    private func remove(_ nodes: [FileNode]) {
        for node in nodes {
            freedBytes += node.size
            guard let parent = node.parent else {
                root = nil
                focus = nil
                continue
            }
            parent.children.removeAll { $0 === node }
            var p: FileNode? = parent
            while let q = p {
                q.size -= node.size
                p = q.parent
            }
            if let f = focus, f.isDescendant(of: node) { focus = parent }
        }
        selection = []
        rebuildSnapshot()
        backStack = backStack.filter { snapshot.index[$0.id] === $0 }
        forwardStack = forwardStack.filter { snapshot.index[$0.id] === $0 }
        dupGroups = dupGroups.compactMap { g in
            let alive = g.nodes.filter { snapshot.index[$0.id] === $0 }
            return alive.count > 1 ? DupGroup(id: g.id, size: g.size, nodes: alive) : nil
        }
        revision += 1
    }

    // MARK: Duplikate

    func findDuplicates() {
        dupContext?.cancel()
        let ctx = ScanContext()
        dupContext = ctx
        dupRunning = true
        dupDone = false
        dupGroups = []
        dupProgress = "Starte …"
        let files = snapshot.files
        let minSize = dupMinSize
        Task { [weak self] in
            let groups = await Task.detached(priority: .userInitiated) {
                DuplicateFinder.find(files: files, minSize: minSize, isCancelled: { ctx.isCancelled }) { text in
                    Task { @MainActor [weak self] in
                        if self?.dupContext === ctx { self?.dupProgress = text }
                    }
                }
            }.value
            guard let self, self.dupContext === ctx else { return }
            self.dupRunning = false
            if !ctx.isCancelled {
                self.dupGroups = groups
                self.dupDone = true
            }
        }
    }

    func cancelDuplicates() {
        dupContext?.cancel()
        dupRunning = false
    }

    /// Markiert in jeder Gruppe alle Kopien außer der ältesten.
    func selectDuplicatesKeepingOldest() {
        var sel: Set<String> = []
        for g in dupGroups {
            let keep = g.nodes.min { ($0.modified ?? .distantFuture) < ($1.modified ?? .distantFuture) }
            for n in g.nodes where n !== keep { sel.insert(n.id) }
        }
        selection = sel
    }

    func keepOnly(_ node: FileNode, in group: DupGroup) {
        selection = Set(group.nodes.filter { $0 !== node }.map(\.id))
    }
}

struct FileRow: Identifiable {
    let node: FileNode
    let depth: Int
    var id: String { node.id }
}
