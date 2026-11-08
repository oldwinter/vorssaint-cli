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
    }

    // Budget: stop parsing transcripts past this many bytes; sessions are still counted.
    static let byteBudget: Int = 250_000_000

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

    static func scanClaude() -> Report {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let files = FileManager.default.fileExists(atPath: dir.path) ? jsonlFiles(under: dir) : []
        var projects = Set<String>()
        var total: Int64 = 0, today: Int64 = 0
        var latest: Date?
        var bytesRead = 0, truncated = false
        for f in files {
            projects.insert(f.deletingLastPathComponent().lastPathComponent)
            let mtime = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let m = mtime, latest.map({ m > $0 }) ?? true { latest = m }
            let size = (try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if size > 60_000_000 || bytesRead > byteBudget { truncated = true; continue }
            bytesRead += size
            guard let data = try? Data(contentsOf: f) else { continue }
            var fileTokens: Int64 = 0
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") where line.contains("\"usage\"") {
                guard let j = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let msg = j["message"] as? [String: Any],
                      let u = msg["usage"] as? [String: Any] else { continue }
                fileTokens += Int64(u["input_tokens"] as? Int ?? 0)
                    + Int64(u["output_tokens"] as? Int ?? 0)
                    + Int64(u["cache_creation_input_tokens"] as? Int ?? 0)
                    + Int64(u["cache_read_input_tokens"] as? Int ?? 0)
            }
            total += fileTokens
            if let m = mtime, isToday(m) { today += fileTokens }
        }
        return Report(agent: "claude", binary: Shell.which("claude"),
                      dataDir: files.isEmpty ? nil : dir.path, sessions: files.count,
                      tokensTotal: total, tokensToday: today,
                      lastActivity: latest.map(iso), projects: projects.count,
                      truncated: truncated)
    }

    static func scanCodex() -> Report {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        var files: [URL] = []
        for sub in ["sessions", "archived_sessions"] {
            let d = base.appendingPathComponent(sub)
            if FileManager.default.fileExists(atPath: d.path) { files += jsonlFiles(under: d) }
        }
        var total: Int64 = 0, today: Int64 = 0
        var latest: Date?
        var bytesRead = 0, truncated = false
        for f in files {
            let mtime = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let m = mtime, latest.map({ m > $0 }) ?? true { latest = m }
            let size = (try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if size > 60_000_000 || bytesRead > byteBudget { truncated = true; continue }
            bytesRead += size
            guard let data = try? Data(contentsOf: f) else { continue }
            var maxTotal: Int64 = 0
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") where line.contains("token_count") {
                guard let j = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let payload = j["payload"] as? [String: Any],
                      let info = payload["info"] as? [String: Any],
                      let usage = info["total_token_usage"] as? [String: Any],
                      let t = usage["total_tokens"] as? Int else { continue }
                maxTotal = max(maxTotal, Int64(t))
            }
            total += maxTotal
            if let m = mtime, isToday(m) { today += maxTotal }
        }
        return Report(agent: "codex", binary: Shell.which("codex"),
                      dataDir: files.isEmpty ? nil : base.appendingPathComponent("sessions").path,
                      sessions: files.count, tokensTotal: total, tokensToday: today,
                      lastActivity: latest.map(iso), projects: nil,
                      truncated: truncated)
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
        let reports = [Agents.scanClaude(), Agents.scanCodex(), Agents.scanOpencode()]
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
