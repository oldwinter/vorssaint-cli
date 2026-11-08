// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation

struct Agents: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "AI agent usage from local session logs (Claude Code, Codex, OpenCode)",
        discussion: """
        Reads local transcripts — no network, no credentials.
          claude   ~/.claude/projects/**/*.jsonl   (usage{} per assistant message)
          codex    ~/.codex/sessions/**/*.jsonl    (token_count cumulative)
          opencode ~/.local/share/opencode         (presence + db size)
        Rate limits live server-side; this reports measured local usage.
        """
    )
    @OptionGroup var g: GlobalOptions

    @Flag(name: .long, help: "Ignore the incremental index and rescan all transcripts")
    var reindex = false

    struct Report: Encodable {
        var agent: String
        var binary: String?
        var dataDir: String?
        var sessions: Int
        var tokensTotal: Int64
        var tokensToday: Int64
        var lastActivity: String?
        var projects: Int?
        var truncated: Bool = false
        var cached: Bool = false
    }

    // Budget: stop parsing transcripts past this many bytes; sessions are still counted.
    static let byteBudget: Int64 = 250_000_000

    // Incremental index at ~/.config/vorssaint/agents-index.json — keyed by file path.
    // `parsedBytes` counts complete lines only, so tail-parsing never starts mid-line.
    struct FileIndex: Codable {
        var size: Int64
        var mtime: Double
        var parsedBytes: Int64
        var tokens: Int64
    }

    struct AgentsIndex: Codable {
        var files: [String: FileIndex] = [:]
    }

    static var indexPath: URL { Store.dir.appendingPathComponent("agents-index.json") }

    static func loadIndex() -> AgentsIndex {
        guard let d = try? Data(contentsOf: indexPath) else { return AgentsIndex() }
        return (try? JSONDecoder().decode(AgentsIndex.self, from: d)) ?? AgentsIndex()
    }

    static func saveIndex(_ i: AgentsIndex) throws {
        try FileManager.default.createDirectory(at: Store.dir, withIntermediateDirectories: true)
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        try e.encode(i).write(to: indexPath, options: .atomic)
    }

    private static func jsonlFiles(under dir: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        for case let u as URL in e where u.pathExtension == "jsonl" { out.append(u) }
        // newest first — token budget covers recent usage when files are huge
        return out.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return a > b
        }
    }

    private static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
        return f.string(from: d)
    }

    private static func isToday(_ d: Date) -> Bool {
        Calendar.current.isDateInToday(d)
    }

    /// Read `url` starting at byte `offset` (0 = whole file).
    private static func readTail(_ url: URL, from offset: Int64) -> Data? {
        guard offset > 0 else { return try? Data(contentsOf: url) }
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        do {
            try h.seek(toOffset: UInt64(offset))
            return try h.readToEnd()
        } catch { return nil }
    }

    /// Bytes through the last '\n' — we only parse and index complete lines.
    private static func coveredBytes(_ d: Data) -> Int64 {
        guard let i = d.lastIndex(of: 0x0A) else { return 0 }
        return Int64(d.distance(from: d.startIndex, to: i)) + 1
    }

    /// Sum claude `usage{}` across complete lines.
    private static func claudeTokens(in lines: Data.SubSequence) -> Int64 {
        var tokens: Int64 = 0
        for line in String(decoding: lines, as: UTF8.self).split(separator: "\n") where line.contains("\"usage\"") {
            guard let j = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let msg = j["message"] as? [String: Any],
                  let u = msg["usage"] as? [String: Any] else { continue }
            tokens += Int64(u["input_tokens"] as? Int ?? 0)
                + Int64(u["output_tokens"] as? Int ?? 0)
                + Int64(u["cache_creation_input_tokens"] as? Int ?? 0)
                + Int64(u["cache_read_input_tokens"] as? Int ?? 0)
        }
        return tokens
    }

    /// Max codex `total_tokens` across complete lines (usage is cumulative per file).
    private static func codexTokens(in lines: Data.SubSequence) -> Int64 {
        var maxTotal: Int64 = 0
        for line in String(decoding: lines, as: UTF8.self).split(separator: "\n") where line.contains("token_count") {
            guard let j = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let payload = j["payload"] as? [String: Any],
                  let info = payload["info"] as? [String: Any],
                  let usage = info["total_token_usage"] as? [String: Any],
                  let t = usage["total_tokens"] as? Int else { continue }
            maxTotal = max(maxTotal, Int64(t))
        }
        return maxTotal
    }

    /// Reuse `index` for unchanged files, tail-parse appended files, rescan the rest.
    /// `fromIndex` reports whether a prior entry served (all or part of) the result.
    private static func scanFile(_ f: URL, size: Int64, mtime: Date?, index: inout AgentsIndex,
                                 reindex: Bool, bytesRead: inout Int64, truncated: inout Bool,
                                 parse: (Data.SubSequence) -> Int64) -> (tokens: Int64, fromIndex: Bool) {
        let key = f.path
        var tokens: Int64 = 0
        var offset: Int64 = 0
        var fromIndex = false
        if !reindex, let e = index.files[key] {
            if e.size == size, e.mtime == (mtime?.timeIntervalSince1970 ?? 0) {
                return (e.tokens, true) // entry stays as-is: parsedBytes may lag size on a partial last line
            } else if size >= e.size, size > e.parsedBytes {
                tokens = e.tokens; offset = e.parsedBytes; fromIndex = true
            }
            // shrank or rewritten → rescan whole file
        }
        if size > offset {
            let toRead = size - offset
            if toRead > 60_000_000 || bytesRead > byteBudget {
                truncated = true
                return (tokens, fromIndex) // keep index entry so the tail can be parsed next run
            }
            guard let data = readTail(f, from: offset) else { return (tokens, fromIndex) }
            let covered = coveredBytes(data)
            tokens += parse(data.prefix(Int(covered)))
            offset += covered
            bytesRead += covered
        }
        index.files[key] = FileIndex(size: size, mtime: mtime?.timeIntervalSince1970 ?? 0,
                                     parsedBytes: offset, tokens: tokens)
        return (tokens, fromIndex)
    }

    static func scanClaude(index: inout AgentsIndex, reindex: Bool) -> Report {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let files = FileManager.default.fileExists(atPath: dir.path) ? jsonlFiles(under: dir) : []
        var projects = Set<String>()
        var total: Int64 = 0, today: Int64 = 0
        var latest: Date?
        var bytesRead: Int64 = 0, truncated = false
        var hits = 0
        for f in files {
            projects.insert(f.deletingLastPathComponent().lastPathComponent)
            let v = try? f.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let mtime = v?.contentModificationDate
            if let m = mtime, latest.map({ m > $0 }) ?? true { latest = m }
            let size = Int64(v?.fileSize ?? 0)
            let r = scanFile(f, size: size, mtime: mtime, index: &index,
                             reindex: reindex, bytesRead: &bytesRead,
                             truncated: &truncated, parse: claudeTokens)
            if r.fromIndex { hits += 1 }
            total += r.tokens
            if let m = mtime, isToday(m) { today += r.tokens }
        }
        return Report(agent: "claude", binary: Shell.which("claude"),
                      dataDir: files.isEmpty ? nil : dir.path, sessions: files.count,
                      tokensTotal: total, tokensToday: today,
                      lastActivity: latest.map(iso), projects: projects.count,
                      truncated: truncated, cached: hits > 0)
    }

    static func scanCodex(index: inout AgentsIndex, reindex: Bool) -> Report {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        var files: [URL] = []
        for sub in ["sessions", "archived_sessions"] {
            let d = base.appendingPathComponent(sub)
            if FileManager.default.fileExists(atPath: d.path) { files += jsonlFiles(under: d) }
        }
        var total: Int64 = 0, today: Int64 = 0
        var latest: Date?
        var bytesRead: Int64 = 0, truncated = false
        var hits = 0
        for f in files {
            let v = try? f.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let mtime = v?.contentModificationDate
            if let m = mtime, latest.map({ m > $0 }) ?? true { latest = m }
            let size = Int64(v?.fileSize ?? 0)
            let r = scanFile(f, size: size, mtime: mtime, index: &index,
                             reindex: reindex, bytesRead: &bytesRead,
                             truncated: &truncated, parse: codexTokens)
            if r.fromIndex { hits += 1 }
            total += r.tokens
            if let m = mtime, isToday(m) { today += r.tokens }
        }
        return Report(agent: "codex", binary: Shell.which("codex"),
                      dataDir: files.isEmpty ? nil : base.appendingPathComponent("sessions").path,
                      sessions: files.count, tokensTotal: total, tokensToday: today,
                      lastActivity: latest.map(iso), projects: nil,
                      truncated: truncated, cached: hits > 0)
    }

    static func scanOpencode() -> Report {
        let db = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/opencode/opencode.db")
        let exists = FileManager.default.fileExists(atPath: db.path)
        var size: Int64 = 0, latest: Date?
        if exists {
            let v = try? db.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            size = Int64(v?.fileSize ?? 0); latest = v?.contentModificationDate
        }
        return Report(agent: "opencode", binary: Shell.which("opencode"),
                      dataDir: exists ? "\(db.path) (\(fmtBytes(UInt64(size))))" : nil,
                      sessions: 0, tokensTotal: 0, tokensToday: 0,
                      lastActivity: latest.map(iso), projects: nil)
    }

    func run() throws {
        wireOutput(g, command: "vorssaint agents")
        var index = reindex ? AgentsIndex() : Agents.loadIndex()
        let reports = [
            Agents.scanClaude(index: &index, reindex: reindex),
            Agents.scanCodex(index: &index, reindex: reindex),
            Agents.scanOpencode(),
        ]
        index.files = index.files.filter { FileManager.default.fileExists(atPath: $0.key) }
        try? Agents.saveIndex(index)
        if Out.json { Out.emit(reports) { "" } }
        else {
            Out.table(["AGENT", "BINARY", "SESSIONS", "TOKENS", "TODAY", "LAST"], rows: reports.map { r in
                [r.agent, r.binary ?? ANSI.dim("not installed"), String(r.sessions),
                 r.tokensTotal > 0 ? fmtTokens(r.tokensTotal) : "-",
                 r.tokensToday > 0 ? fmtTokens(r.tokensToday) : "-",
                 r.lastActivity ?? "-"]
            })
        }
    }
}

func fmtTokens(_ t: Int64) -> String {
    if t >= 1_000_000 { return String(format: "%.1fM", Double(t) / 1_000_000) }
    if t >= 1_000 { return String(format: "%.1fK", Double(t) / 1_000) }
    return "\(t)"
}
