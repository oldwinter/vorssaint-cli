// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation

struct Trash: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Inspect and empty the Trash",
        subcommands: [List.self, Empty.self],
        defaultSubcommand: List.self
    )

    struct Item: Encodable { var name: String, bytes: Int64 }

    static func items() -> [Item] {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: trash.path) else { return [] }
        return names.filter { !$0.hasPrefix(".") }.map { n in
            let p = trash.appendingPathComponent(n)
            var size: Int64 = 0
            if let s = try? FileManager.default.allocatedSizeOfDirectory(at: p) { size = s }
            else if let a = try? FileManager.default.attributesOfItem(atPath: p.path) { size = (a[.size] as? Int64) ?? 0 }
            return Item(name: n, bytes: size)
        }.sorted { $0.bytes > $1.bytes }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List trash contents and total size")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint trash")
            let items = Trash.items()
            if Out.json {
                struct R: Encodable { var items: [Item], totalBytes: Int64 }
                Out.emit(R(items: items, totalBytes: items.reduce(0) { $0 + $1.bytes })) { "" }
            } else {
                print(ANSI.dim("\(items.count) items, \(fmtBytes(UInt64(items.reduce(0) { $0 + $1.bytes })))"))
                Out.table(["SIZE", "NAME"], rows: items.prefix(50).map { [fmtBytes(UInt64($0.bytes)), $0.name] })
            }
        }
    }

    struct Empty: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Empty the trash")
        @OptionGroup var g: GlobalOptions
        @Flag(name: .long) var yes = false
        @Flag(name: .long) var dryRun = false
        func run() throws {
            wireOutput(g, command: "vorssaint trash empty")
            let items = Trash.items()
            let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
            if dryRun {
                struct R: Encodable { var wouldDelete: Int, bytes: Int64 }
                Out.emit(R(wouldDelete: items.count, bytes: items.reduce(0) { $0 + $1.bytes })) {
                    "would delete \(items.count) items (\(fmtBytes(UInt64(items.reduce(0) { $0 + $1.bytes }))))"
                }
                return
            }
            Out.confirm("Permanently delete \(items.count) items (\(fmtBytes(UInt64(items.reduce(0) { $0 + $1.bytes }))))?", yes: yes)
            var deleted = 0, failed = 0
            for i in items {
                do { try FileManager.default.removeItem(at: trash.appendingPathComponent(i.name)); deleted += 1 }
                catch { failed += 1 }
            }
            struct R: Encodable { var deleted: Int, failed: Int }
            Out.emit(R(deleted: deleted, failed: failed)) { "deleted \(deleted) items" + (failed > 0 ? " — \(failed) failed" : "") }
        }
    }
}

extension FileManager {
    func allocatedSizeOfDirectory(at url: URL) throws -> Int64 {
        guard let e = enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            if let v = try? f.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]), !(v.isDirectory ?? false) {
                total += Int64(v.fileSize ?? 0)
            }
        }
        return total
    }
}
