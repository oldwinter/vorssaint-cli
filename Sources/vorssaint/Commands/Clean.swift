// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation

struct Clean: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Scan and clean caches (moves to Trash, recoverable)",
        subcommands: [Scan.self, Run.self],
        defaultSubcommand: Scan.self
    )

    struct Entry: Encodable { var path: String, name: String, bytes: Int64, ageDays: Int }

    static func scanCaches() -> [Entry] {
        let fm = FileManager.default
        let roots = [
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs"),
        ]
        var out: [Entry] = []
        for root in roots {
            guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { continue }
            for n in names where !n.hasPrefix(".") {
                let u = root.appendingPathComponent(n)
                var size: Int64 = (try? fm.allocatedSizeOfDirectory(at: u)) ?? 0
                if size == 0, let a = try? fm.attributesOfItem(atPath: u.path) { size = (a[.size] as? Int64) ?? 0 }
                guard size > 1_000_000 else { continue } // only ≥1MB entries are interesting
                let mtime = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                let age = mtime.map { Int(Date().timeIntervalSince($0) / 86400) } ?? 0
                out.append(Entry(path: u.path, name: n, bytes: size, ageDays: age))
            }
        }
        return out.sorted { $0.bytes > $1.bytes }
    }

    static func filtered(_ entries: [Entry], match: String?, olderThan: Int?) -> [Entry] {
        entries.filter { e in
            if let match, !e.name.localizedCaseInsensitiveContains(match) { return false }
            if let olderThan, e.ageDays < olderThan { return false }
            return true
        }
    }

    struct Scan: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show largest cache/log entries under ~/Library")
        @OptionGroup var g: GlobalOptions
        @Option(help: "Filter by name substring") var match: String?
        @Option(help: "Only entries untouched for N days") var olderThan: Int?
        @Option(help: "Max rows") var limit: Int = 40
        func run() throws {
            wireOutput(g, command: "vorssaint clean scan")
            let rows = Clean.filtered(Clean.scanCaches(), match: match, olderThan: olderThan)
            if Out.json {
                struct R: Encodable { var entries: [Entry], totalBytes: Int64 }
                Out.emit(R(entries: rows, totalBytes: rows.reduce(0) { $0 + $1.bytes })) { "" }
            } else {
                print(ANSI.dim("\(rows.count) entries ≥1MB — \(fmtBytes(UInt64(rows.reduce(0) { $0 + $1.bytes }))) total"))
                Out.table(["SIZE", "AGE", "NAME"], rows: rows.prefix(limit).map {
                    [fmtBytes(UInt64($0.bytes)), "\($0.ageDays)d", $0.name]
                })
            }
        }
    }

    struct Run: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Move matching cache entries to the Trash",
            discussion: "Safer than rm: recoverable from Trash until emptied. Default scope = biggest offenders."
        )
        @OptionGroup var g: GlobalOptions
        @Option(help: "Only names matching this substring") var match: String?
        @Option(help: "Only entries untouched for N days") var olderThan: Int?
        @Option(help: "Limit to N biggest entries") var limit: Int = 20
        @Flag(name: .long) var dryRun = false
        @Flag(name: .long) var yes = false
        func run() throws {
            wireOutput(g, command: "vorssaint clean run")
            let rows = Array(Clean.filtered(Clean.scanCaches(), match: match, olderThan: olderThan).prefix(limit))
            if rows.isEmpty { Out.emit([Entry]()) { "nothing matched" }; return }
            let total = rows.reduce(0) { $0 + $1.bytes }
            if dryRun {
                struct R: Encodable { var wouldTrash: Int, bytes: Int64 }
                Out.emit(R(wouldTrash: rows.count, bytes: total)) {
                    "would trash \(rows.count) entries (\(fmtBytes(UInt64(total))))\n" + rows.map { "  \($0.name)" }.joined(separator: "\n")
                }
                return
            }
            Out.confirm("Move \(rows.count) entries (\(fmtBytes(UInt64(total)))) to Trash?", yes: yes)
            var trashed = 0, failed = 0
            for e in rows {
                do { try FileManager.default.trashItem(at: URL(fileURLWithPath: e.path), resultingItemURL: nil); trashed += 1 }
                catch { failed += 1 }
            }
            struct R: Encodable { var trashed: Int, failed: Int, bytes: Int64 }
            Out.emit(R(trashed: trashed, failed: failed, bytes: total)) {
                "trashed \(trashed) entries (\(fmtBytes(UInt64(total))))" + (failed > 0 ? " — \(failed) failed (app running?)" : "")
            }
        }
    }
}
