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
    var name: String
    let isDirectory: Bool
    var isHidden = false
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

/// Dezimale Einheiten wie im Finder, immer drei signifikante Stellen: 95,9 GB · 4,51 GB · 471 GB.
func formatBytes(_ n: Int64) -> String {
    guard n > 0 else { return "0 KB" }
    let units = ["Byte", "KB", "MB", "GB", "TB", "PB"]
    var value = Double(n)
    var unit = 0
    while value >= 999.5, unit < units.count - 1 {
        value /= 1000
        unit += 1
    }
    let digits = unit == 0 || value >= 99.95 ? 0 : value >= 9.995 ? 1 : 2
    return value.formatted(.number.precision(.fractionLength(digits))) + " " + units[unit]
}

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
        .contentModificationDateKey, .isHiddenKey,
    ]

    /// Pfade, die beim Scannen von „/“ Daten doppelt zählen würden (Firmlinks) oder keine echten Dateien sind.
    private static let skipPaths: Set<String> = ["/System/Volumes", "/Volumes", "/dev"]

    static func scan(_ url: URL, context: ScanContext) -> FileNode {
        let root = FileNode(url: url, isDirectory: true, size: 0)
        if url.path == "/", let name = try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName {
            root.name = name
        }
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
                child.isHidden = v?.isHidden == true || u.lastPathComponent.hasPrefix(".")
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
            // Innerhalb eines App-Pakets gehört der Ordner zur App und wäre nicht wiederherstellbar.
            case "node_modules" where !n.url.path.contains(".app/"): return "Node-Abhängigkeiten – mit „npm install“ jederzeit wiederherstellbar"
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

enum MainTab: String, CaseIterable, Identifiable {
    case structure, largest
    var id: String { rawValue }
    var label: String { self == .structure ? "Ordnerstruktur" : "Größte Dateien" }
}

enum CleanTab: String, CaseIterable, Identifiable {
    case cleanup, duplicates, types
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cleanup: "Aufräumen"
        case .duplicates: "Duplikate"
        case .types: "Typen"
        }
    }
}

/// Inhalt einer Spalte: große Objekte einzeln, der Rest in zwei Sammelzeilen.
struct ColumnContent {
    static let maxShown = 10
    static let minShownSize: Int64 = 100_000

    var shown: [FileNode] = []
    var small: [FileNode] = []
    var hidden: [FileNode] = []

    var smallSize: Int64 { small.reduce(0) { $0 + $1.size } }
    var hiddenSize: Int64 { hidden.reduce(0) { $0 + $1.size } }

    init(_ folder: FileNode) {
        for c in folder.children {   // nach Größe sortiert
            if c.isHidden {
                hidden.append(c)
            } else if shown.count < Self.maxShown, c.size >= Self.minShownSize {
                shown.append(c)
            } else {
                small.append(c)
            }
        }
    }
}

enum ColumnGroup: String {
    case small, hidden
    func key(in folder: FileNode) -> String { folder.id + "#" + rawValue }
}

struct SidebarLocation: Identifiable, Hashable {
    let title: String
    let symbol: String
    let url: URL
    var id: String { url.path }
}

/// Ergebnis eines Scans, damit der Wechsel zwischen Speicherorten sofort geht.
struct CachedScan {
    let root: FileNode
    var snapshot: Snapshot
    var items: Int
    var skipped: Int
    var freed: Int64
}

func isPath(_ path: String, inside parent: String) -> Bool {
    parent == "/" || path == parent || path.hasPrefix(parent + "/")
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
    /// Die im Diagramm und in den Spalten hervorgehobene Datei (Ordner stehen in `focus`).
    var focusedFile: FileNode?
    /// Angehakte Objekte.
    var selection: Set<String> = []
    /// Aufgeklappte Sammelzeilen („Kleine“/„Versteckte Elemente“).
    var expandedGroups: Set<String> = []
    var revision = 0
    var isScanning = false
    var scannedItems = 0
    var skippedFolders = 0
    var lastURL: URL?
    private(set) var snapshot = Snapshot()
    private(set) var backStack: [FileNode] = []
    private(set) var forwardStack: [FileNode] = []

    // Ansicht
    var mainTab: MainTab = .structure
    var cleanTab: CleanTab = .cleanup
    var showCleanSheet = false
    var showHelp = false
    var sidebarVisible = true
    var searchVisible = false
    var colorMode: ChartColorMode = .folder
    var searchText = ""
    var kindFilter: FileKind?
    var ageFilter: AgeFilter = .all

    // Datenträger / Sitzung
    var volumeTotal: Int64 = 0
    var volumeFree: Int64 = 0
    var freedBytes: Int64 = 0
    var recents: [String] = UserDefaults.standard.stringArray(forKey: "recents") ?? []
    var customFolders: [String] = UserDefaults.standard.stringArray(forKey: "customFolders") ?? []
    private(set) var scans: [String: CachedScan] = [:]

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
        if panel.runModal() == .OK, let url = panel.url {
            let known = homeLocation.url.path == url.path
                || volumeLocations().contains { $0.id == url.path }
                || standardFolders().contains { $0.id == url.path }
            if !known, !customFolders.contains(url.path) {
                customFolders.append(url.path)
                UserDefaults.standard.set(customFolders, forKey: "customFolders")
            }
            show(url)
        }
    }

    func removeCustomFolder(_ path: String) {
        customFolders.removeAll { $0 == path }
        UserDefaults.standard.set(customFolders, forKey: "customFolders")
    }

    // MARK: Speicherorte der Seitenleiste

    var homeLocation: SidebarLocation {
        SidebarLocation(title: NSUserName(), symbol: "house.fill", url: FileManager.default.homeDirectoryForCurrentUser)
    }

    func volumeLocations() -> [SidebarLocation] {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeIsInternalKey]
        let vols = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return vols.compactMap { v in
            let values = try? v.resourceValues(forKeys: Set(keys))
            guard v.path == "/" || v.path.hasPrefix("/Volumes/") else { return nil }
            return SidebarLocation(title: values?.volumeLocalizedName ?? v.lastPathComponent,
                                   symbol: values?.volumeIsInternal == false ? "externaldrive.fill" : "internaldrive.fill",
                                   url: v)
        }
    }

    func standardFolders() -> [SidebarLocation] {
        let fm = FileManager.default
        let entries: [(String, String, FileManager.SearchPathDirectory)] = [
            ("Schreibtisch", "menubar.dock.rectangle", .desktopDirectory),
            ("Downloads", "arrow.down.circle.fill", .downloadsDirectory),
            ("Bilder", "camera.fill", .picturesDirectory),
            ("Dokumente", "doc.fill", .documentDirectory),
        ]
        var out = entries.compactMap { e in
            fm.urls(for: e.2, in: .userDomainMask).first.map { SidebarLocation(title: e.0, symbol: e.1, url: $0) }
        }
        out.append(SidebarLocation(title: "Programme", symbol: "square.grid.2x2.fill", url: URL(fileURLWithPath: "/Applications")))
        return out
    }

    func customLocations() -> [SidebarLocation] {
        customFolders.map {
            SidebarLocation(title: ($0 as NSString).lastPathComponent, symbol: "folder.fill", url: URL(fileURLWithPath: $0))
        }
    }

    /// Zeigt einen Speicherort: aus dem Zwischenspeicher, sonst per neuem Scan.
    func show(_ url: URL) {
        guard let cached = scans[url.path] else { scan(url); return }
        guard root !== cached.root else { return }
        context?.cancel()
        context = nil
        isScanning = false
        dupContext?.cancel()
        resetView()
        lastURL = url
        root = cached.root
        focus = cached.root
        snapshot = cached.snapshot
        scannedItems = cached.items
        skippedFolders = cached.skipped
        freedBytes = cached.freed
        updateVolume()
        revision += 1
    }

    private func resetView() {
        root = nil
        focus = nil
        focusedFile = nil
        backStack = []
        forwardStack = []
        selection = []
        expandedGroups = []
        snapshot = Snapshot()
        dupGroups = []
        dupDone = false
        dupRunning = false
        kindFilter = nil
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
        scans[url.path] = nil
        resetView()
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
            self.scans[url.path] = CachedScan(root: result.0, snapshot: result.1, items: ctx.items, skipped: ctx.skipped, freed: 0)
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

    /// Hakt ein Objekt an oder ab. Liegt es in einem angehakten Ordner, ist es dadurch schon erfasst.
    func toggleChecked(_ node: FileNode) {
        guard !isCoveredByParent(node) else { return }
        if selection.contains(node.id) { selection.remove(node.id) } else { selection.insert(node.id) }
    }

    func isCoveredByParent(_ node: FileNode) -> Bool {
        var p = node.parent
        while let q = p {
            if selection.contains(q.id) { return true }
            p = q.parent
        }
        return false
    }

    /// Macht ein Objekt zum aktuellen Eintrag in Spalten, Pfadleiste und Diagramm.
    func activate(_ node: FileNode) {
        var n: FileNode? = node
        while let c = n, let parent = c.parent {
            if c.isHidden {
                expandedGroups.insert(ColumnGroup.hidden.key(in: parent))
            } else if ColumnContent(parent).small.contains(where: { $0 === c }) {
                expandedGroups.insert(ColumnGroup.small.key(in: parent))
            }
            n = parent
        }
        if node.isDirectory {
            navigate(to: node)
        } else {
            navigate(to: node.parent ?? node)
            focusedFile = node
        }
    }

    /// Mitte des Diagramms: eine Ebene über dem aktuellen Ordner, damit dieser als Ring sichtbar bleibt.
    var chartCenter: FileNode? { focus?.parent ?? focus }

    var cursor: FileNode? { focusedFile ?? focus }

    func visibleItems(in folder: FileNode) -> [FileNode] {
        let c = ColumnContent(folder)
        var out = c.shown
        if expandedGroups.contains(ColumnGroup.small.key(in: folder)) { out += c.small }
        if expandedGroups.contains(ColumnGroup.hidden.key(in: folder)) { out += c.hidden }
        return out
    }

    /// Pfeiltasten ↑/↓: nächster sichtbarer Eintrag derselben Spalte.
    func moveCursor(by delta: Int) {
        guard let cur = cursor else { return }
        guard let parent = cur.parent else { cursorIn(); return }
        let items = visibleItems(in: parent)
        guard let i = items.firstIndex(where: { $0 === cur }), items.indices.contains(i + delta) else { return }
        activate(items[i + delta])
    }

    func cursorIn() {
        guard let cur = cursor, cur.isDirectory, let first = visibleItems(in: cur).first else { return }
        activate(first)
    }

    func cursorOut() {
        if let parent = cursor?.parent { activate(parent) }
    }

    func toggleGroup(_ group: ColumnGroup, in folder: FileNode) {
        let key = group.key(in: folder)
        if expandedGroups.contains(key) { expandedGroups.remove(key) } else { expandedGroups.insert(key) }
    }

    /// Wechselt den im Diagramm gezeigten Ordner und merkt sich den Verlauf.
    func navigate(to node: FileNode) {
        focusedFile = nil
        guard node !== focus else { return }
        if let f = focus { backStack.append(f) }
        forwardStack = []
        focus = node
        revision += 1
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
            focusedFile = nil
            focus = prev
            revision += 1
            return
        }
    }

    func goForward() {
        while let next = forwardStack.popLast() {
            guard snapshot.index[next.id] === next else { continue }
            if let f = focus { backStack.append(f) }
            focusedFile = nil
            focus = next
            revision += 1
            return
        }
    }

    /// Zeigt ein Objekt in Spalten und Diagramm.
    func showInChart(_ node: FileNode) {
        showCleanSheet = false
        mainTab = .structure
        activate(node)
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

    /// `permanent == nil` lässt im Dialog die Wahl zwischen Papierkorb und endgültigem Löschen.
    func confirmAndDelete(_ nodes: [FileNode], permanent requested: Bool? = nil) {
        let top = pruned(nodes)
        guard !top.isEmpty else { return }
        let total = top.reduce(Int64(0)) { $0 + $1.size }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = top.count == 1 ? "„\(top[0].name)“ löschen?" : "\(top.count) Objekte löschen?"
        let summary = top.count == 1
            ? "\(formatBytes(total)) · \(top[0].url.path)"
            : "Zusammen \(formatBytes(total))"
        alert.informativeText = requested == true ? summary + "\n\nDas lässt sich nicht rückgängig machen." : summary

        let permanent: Bool
        if let requested {
            alert.addButton(withTitle: requested ? "Endgültig löschen" : "In den Papierkorb")
            alert.addButton(withTitle: "Abbrechen")
            alert.buttons[0].hasDestructiveAction = requested
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            permanent = requested
        } else {
            alert.addButton(withTitle: "In den Papierkorb")
            alert.addButton(withTitle: "Endgültig löschen")
            alert.addButton(withTitle: "Abbrechen")
            alert.buttons[1].hasDestructiveAction = true
            switch alert.runModal() {
            case .alertFirstButtonReturn: permanent = false
            case .alertSecondButtonReturn: permanent = true
            default: return
            }
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
            if let f = focusedFile, f.isDescendant(of: node) { focusedFile = nil }
        }
        selection = []
        rebuildSnapshot()
        syncCache(after: nodes)
        backStack = backStack.filter { snapshot.index[$0.id] === $0 }
        forwardStack = forwardStack.filter { snapshot.index[$0.id] === $0 }
        dupGroups = dupGroups.compactMap { g in
            let alive = g.nodes.filter { snapshot.index[$0.id] === $0 }
            return alive.count > 1 ? DupGroup(id: g.id, size: g.size, nodes: alive) : nil
        }
        revision += 1
    }

    /// Hält den aktuellen Scan aktuell und verwirft andere, die das Gelöschte enthalten.
    private func syncCache(after removed: [FileNode]) {
        let current = lastURL?.path
        if let current, scans[current] != nil {
            scans[current]?.snapshot = snapshot
            scans[current]?.freed = freedBytes
        }
        for key in scans.keys where key != current {
            if removed.contains(where: { isPath($0.url.path, inside: key) || isPath(key, inside: $0.url.path) }) {
                scans[key] = nil
            }
        }
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
