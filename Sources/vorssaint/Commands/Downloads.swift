// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ArgumentParser
import Foundation

// ~/Downloads inspection and optional tidying. Everything that moves files is
// dry-run-first and never deletes: organize only rearranges inside Downloads.

struct Downloads: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Inspect and organize ~/Downloads",
        discussion: """
        `list` groups downloads by source app (quarantine attribute, then
        kMDItemWhereFroms) or by age/type. `organize` moves classified files
        into subfolders and previews unless --yes is given.

          vorssaint downloads list --by source
          vorssaint downloads organize --dry-run
          vorssaint downloads organize --by type --yes
        """,
        subcommands: [List.self, Organize.self],
        defaultSubcommand: List.self
    )

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }

    // MARK: - Classification

    enum Kind: String, CaseIterable {
        case documents = "Documents", images = "Images", archives = "Archives", installers = "Installers"
        case audio = "Audio", video = "Video", code = "Code", other = "Other"

        var folder: String? { self == .other ? nil : rawValue }
    }

    static let kinds: [Kind: Set<String>] = [
        .documents: ["pdf", "doc", "docx", "txt", "md", "rtf", "pages", "epub", "csv", "xls", "xlsx",
                     "ppt", "pptx", "key", "numbers", "odt", "ods", "odp"],
        .images: ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp", "svg", "ico", "raw", "dng"],
        .archives: ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "zst", "lz4"],
        .installers: ["dmg", "pkg", "mpkg", "app", "iso", "exe", "msi"],
        .audio: ["mp3", "m4a", "wav", "flac", "aiff", "aac", "ogg", "opus"],
        .video: ["mp4", "mov", "m4v", "mkv", "avi", "webm", "flv"],
        .code: ["swift", "js", "ts", "jsx", "tsx", "py", "json", "yaml", "yml", "sh", "html", "css",
                "toml", "rs", "go", "c", "h", "cpp", "hpp", "java", "rb", "php", "sql"],
    ]

    static func kind(of url: URL) -> Kind {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return .other }
        for (kind, exts) in kinds where exts.contains(ext) { return kind }
        return .other
    }

    struct Item: Encodable {
        var name: String, path: String, bytes: Int, modified: String
        var source: String, kind: String
    }

    static func items(in dir: URL) -> [Item] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        let iso = ISO8601DateFormatter()
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.isRegularFile == true else { return nil }
            let size = v.fileSize ?? 0
            let date = v.contentModificationDate ?? Date.distantPast
            return Item(name: url.lastPathComponent, path: url.path, bytes: size,
                        modified: iso.string(from: date),
                        source: source(of: url),
                        kind: kind(of: url).rawValue)
        }
    }

    /// Quarantine stores `flags;timestamp;agent;uuid`; mdls holds the
    /// originating URL for files that predate or lost the attribute.
    static func source(of url: URL) -> String {
        if let agent = quarantineAgent(url.path), !agent.isEmpty { return agent }
        if let host = whereFromHost(url.path), !host.isEmpty { return host }
        return "local"
    }

    private static func quarantineAgent(_ path: String) -> String? {
        let name = "com.apple.quarantine"
        let size = getxattr(path, name, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: size)
        let n = getxattr(path, name, &data, size, 0, 0)
        guard n > 0 else { return nil }
        let fields = String(decoding: data.prefix(n), as: UTF8.self)
            .split(separator: ";", omittingEmptySubsequences: false)
        guard fields.count >= 3 else { return nil }
        return String(fields[2])
    }

    private static func whereFromHost(_ path: String) -> String? {
        let r = Shell.run("/usr/bin/mdls", ["-name", "kMDItemWhereFroms", "-raw", path])
        guard r.status == 0 else { return nil }
        guard let range = r.stdout.range(of: "https?://", options: .regularExpression) else { return nil }
        let tail = r.stdout[range.lowerBound...]
        let urlText = tail.prefix { !$0.isWhitespace && $0 != "\"" && $0 != ")" && $0 != "," }
        return URL(string: String(urlText))?.host
    }

    static func ageBucket(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        guard let d = f.date(from: iso) else { return "older" }
        let days = Int(Date().timeIntervalSince(d) / 86_400)
        switch days {
        case ..<1: return "today"
        case 1..<7: return "last 7 days"
        case 7..<30: return "last 30 days"
        default: return "older"
        }
    }

    // MARK: - list

    struct Group: Encodable { var key: String, count: Int, bytes: Int }

    struct ListResult: Encodable {
        var directory: String, count: Int, bytes: Int, by: String
        var groups: [Group], files: [Item]
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List downloads grouped by source, age or type")
        @OptionGroup var g: GlobalOptions
        @Option(name: .long, help: "Group by: source | age | type") var by: String = "source"
        @Flag(name: .long, help: "Include the per-file table") var files = false

        func run() throws {
            wireOutput(g, command: "vorssaint downloads list")
            guard ["source", "age", "type"].contains(by) else {
                throw ValidationError("--by must be source, age or type")
            }
            let dir = Downloads.directory
            guard FileManager.default.fileExists(atPath: dir.path) else {
                Out.fail("not_found", "no Downloads folder at \(dir.path)", exit: .notFound)
            }
            let all = Downloads.items(in: dir).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            let groups: [Group]
            switch by {
            case "age":
                groups = Dictionary(grouping: all, by: { Downloads.ageBucket($0.modified) })
                    .map { Group(key: $0.key, count: $0.value.count, bytes: $0.value.reduce(0) { $0 + $1.bytes }) }
                    .sorted { $0.key < $1.key }
            case "type":
                groups = Dictionary(grouping: all, by: \.kind)
                    .map { Group(key: $0.key, count: $0.value.count, bytes: $0.value.reduce(0) { $0 + $1.bytes }) }
                    .sorted { $0.bytes > $1.bytes }
            default:
                groups = Dictionary(grouping: all, by: \.source)
                    .map { Group(key: $0.key, count: $0.value.count, bytes: $0.value.reduce(0) { $0 + $1.bytes }) }
                    .sorted { $0.count > $1.count }
            }
            let total = all.reduce(0) { $0 + $1.bytes }
            let result = ListResult(directory: dir.path, count: all.count, bytes: total,
                                    by: by, groups: groups, files: all)

            if Out.json { Out.emit(result) { "" }; return }
            print(ANSI.bold("\(all.count) files, \(fmtBytes(UInt64(total)))") + ANSI.dim("  \(dir.path)"))
            Out.table([by.uppercased(), "COUNT", "SIZE"], rows: groups.map {
                [$0.key, String($0.count), fmtBytes(UInt64($0.bytes))]
            })
            if files {
                print("")
                Out.table(["FILE", "SIZE", "SOURCE", "KIND"], rows: all.map {
                    [$0.name, fmtBytes(UInt64($0.bytes)), $0.source, $0.kind]
                })
            }
        }
    }

    // MARK: - organize

    struct Move: Encodable { var from: String, to: String }

    struct OrganizeResult: Encodable {
        var directory: String, dryRun: Bool, moved: [Move], skipped: Int, bytes: Int
    }

    struct Organize: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Move classified downloads into subfolders (preview by default)",
            discussion: "Only rearranges files inside ~/Downloads; nothing is deleted."
        )
        @OptionGroup var g: GlobalOptions
        @Option(name: .long, help: "Group by: type") var by: String = "type"
        @Flag(name: .long, help: "Preview moves without touching files") var dryRun = false
        @Flag(name: .long, help: "Apply the moves") var yes = false

        func run() throws {
            wireOutput(g, command: "vorssaint downloads organize")
            guard by == "type" else { throw ValidationError("--by currently supports only: type") }
            let dir = Downloads.directory
            guard FileManager.default.fileExists(atPath: dir.path) else {
                Out.fail("not_found", "no Downloads folder at \(dir.path)", exit: .notFound)
            }

            // Plan first so --dry-run and the confirmation can show real work.
            var plan: [(URL, URL)] = []
            var skipped = 0
            for item in Downloads.items(in: dir) {
                let url = URL(fileURLWithPath: item.path)
                let kind = Downloads.kind(of: url)
                guard let folder = kind.folder else { skipped += 1; continue }
                let dest = Downloads.uniqueDestination(dir.appendingPathComponent(folder, isDirectory: true),
                                                       name: item.name)
                plan.append((url, dest))
            }
            plan.sort { $0.0.lastPathComponent < $1.0.lastPathComponent }
            let bytes = plan.reduce(0) { sum, pair in
                sum + ((try? pair.0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }

            let result = OrganizeResult(directory: dir.path, dryRun: dryRun,
                                        moved: plan.map { Move(from: $0.0.path, to: $0.1.path) },
                                        skipped: skipped, bytes: bytes)
            if dryRun {
                emit(result, planned: true)
                return
            }
            if plan.isEmpty {
                Out.emit(result) { "nothing to organize — no classified files in \(dir.path)" }
                return
            }
            Out.confirm("Move \(plan.count) file(s) into subfolders in \(dir.path)?", yes: yes)
            var moved: [Move] = []
            for (src, dst) in plan {
                do {
                    try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true)
                    try FileManager.default.moveItem(at: src, to: dst)
                    moved.append(Move(from: src.path, to: dst.path))
                } catch {
                    skipped += 1
                }
            }
            emit(OrganizeResult(directory: dir.path, dryRun: false, moved: moved,
                                skipped: skipped, bytes: bytes), planned: false)
        }

        private func emit(_ r: OrganizeResult, planned: Bool) {
            if Out.json { Out.emit(r) { "" }; return }
            let verb = planned ? "would move" : "moved"
            if r.moved.isEmpty {
                print("\(verb) 0 files (\(r.skipped) unclassified left in place)")
                return
            }
            Out.table(["FROM", "TO"], rows: r.moved.map {
                [(($0.from as NSString).lastPathComponent),
                 URL(fileURLWithPath: $0.to).deletingLastPathComponent().lastPathComponent]
            })
            print("\(verb) \(r.moved.count) file(s), \(fmtBytes(UInt64(r.bytes)))"
                + (r.skipped > 0 ? " — \(r.skipped) unclassified left in place" : ""))
        }
    }

    /// Avoid clobbering: `name.ext`, `name 2.ext`, `name 3.ext`, …
    static func uniqueDestination(_ dir: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = dir.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let next = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            candidate = dir.appendingPathComponent(next)
            n += 1
        }
        return candidate
    }
}
