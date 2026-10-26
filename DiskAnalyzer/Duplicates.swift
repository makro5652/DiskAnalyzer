import CryptoKit
import Darwin
import Foundation

struct DupGroup: Identifiable {
    let id: Int
    let size: Int64          // tatsächliche Dateigröße
    var nodes: [FileNode]
    var wasted: Int64 { size * Int64(nodes.count - 1) }
}

enum DuplicateFinder {
    private struct Inode: Hashable { let dev: Int64; let ino: UInt64 }

    /// Gleiche Größe → gleicher Anfang (64 KB) → gleicher Gesamt-Hash (SHA-256).
    /// Hardlinks (gleiche Inode) zählen nicht als Duplikat, da sie keinen Platz verschwenden.
    static func find(
        files: [FileNode], minSize: Int64,
        isCancelled: @Sendable () -> Bool,
        progress: @Sendable (String) -> Void
    ) -> [DupGroup] {
        // 1. Nach tatsächlicher Größe gruppieren
        let candidates = files.prefix { $0.size >= minSize }
        var bySize: [Int64: [FileNode]] = [:]
        var seen: [Int64: Set<Inode>] = [:]
        var n = 0
        for f in candidates {
            if isCancelled() { return [] }
            n += 1
            if n % 500 == 0 { progress("Lese Dateigrößen … \(n) / \(candidates.count)") }
            var st = stat()
            guard stat(f.url.path, &st) == 0, st.st_size >= minSize else { continue }
            let ino = Inode(dev: Int64(st.st_dev), ino: UInt64(st.st_ino))
            if !seen[Int64(st.st_size), default: []].insert(ino).inserted { continue }
            bySize[Int64(st.st_size), default: []].append(f)
        }
        let sizeGroups = bySize.filter { $0.value.count > 1 }

        // 2. Anfang hashen
        let total1 = sizeGroups.values.reduce(0) { $0 + $1.count }
        var done = 0
        var partial: [[FileNode]] = []
        var sizeOf: [ObjectIdentifier: Int64] = [:]
        for (size, nodes) in sizeGroups {
            var byHash: [Data: [FileNode]] = [:]
            for f in nodes {
                if isCancelled() { return [] }
                done += 1
                if done % 20 == 0 { progress("Vergleiche Dateianfänge … \(done) / \(total1)") }
                guard let h = hash(f.url, limit: 65_536, isCancelled: isCancelled) else { continue }
                byHash[h, default: []].append(f)
            }
            for g in byHash.values where g.count > 1 {
                partial.append(g)
                for f in g { sizeOf[ObjectIdentifier(f)] = size }
            }
        }

        // 3. Vollständig hashen
        let total2 = partial.reduce(0) { $0 + $1.count }
        done = 0
        var result: [DupGroup] = []
        for g in partial {
            var byHash: [Data: [FileNode]] = [:]
            for f in g {
                if isCancelled() { return [] }
                done += 1
                progress("Prüfe Inhalt … \(done) / \(total2) · \(f.name)")
                guard let h = hash(f.url, limit: nil, isCancelled: isCancelled) else { continue }
                byHash[h, default: []].append(f)
            }
            for same in byHash.values where same.count > 1 {
                result.append(DupGroup(id: 0, size: sizeOf[ObjectIdentifier(same[0])] ?? same[0].size, nodes: same))
            }
        }

        result.sort { $0.wasted > $1.wasted }
        return result.enumerated().map { DupGroup(id: $0.offset, size: $0.element.size, nodes: $0.element.nodes) }
    }

    private static func hash(_ url: URL, limit: Int?, isCancelled: () -> Bool) -> Data? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            if isCancelled() { return nil }
            let chunk: Data? = autoreleasepool { try? h.read(upToCount: min(1 << 20, remaining)) }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            remaining -= chunk.count
        }
        return Data(hasher.finalize())
    }
}
