// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation

// Markdown scratchpad: plain files under ~/.config/vorssaint/notes/ so agents
// can append a thought and humans can open the same file in $EDITOR.

struct Note: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Markdown scratchpad notes",
        discussion: """
        Notes are plain .md files in ~/.config/vorssaint/notes/. One-daily-note
        model: `note "text"` appends to today's file; `note` with no argument
        opens $EDITOR.

          vorssaint note "remember to check the build"
          echo "- idea" | vorssaint note
          vorssaint note list
          vorssaint note show [today|<name>]
          vorssaint note edit [name]
        """,
        subcommands: [Add.self, List.self, Show.self, Edit.self],
        defaultSubcommand: Add.self,
        aliases: ["notes", "scratch"]
    )

    static var directory: URL {
        Store.dir.appendingPathComponent("notes", isDirectory: true)
    }

    static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Map a user-facing name to a file inside the notes directory.
    /// "today" is an alias; path separators and traversal are rejected.
    static func url(for name: String?) throws -> URL {
        var raw = (name ?? "today").trimmingCharacters(in: .whitespaces)
        if raw.isEmpty { raw = "today" }
        if raw.lowercased() == "today" { raw = today() }
        guard !raw.contains("/"), !raw.contains(":"), raw != ".", raw != "..", !raw.hasPrefix(".") else {
            throw ValidationError("invalid note name '\(raw)' — use a plain file name")
        }
        if !raw.lowercased().hasSuffix(".md") { raw += ".md" }
        return directory.appendingPathComponent(raw)
    }

    static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func notes() -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return urls.filter { $0.pathExtension.lowercased() == "md" }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
    }

    static func openInEditor(_ url: URL) -> Int32 {
        let editor = ProcessInfo.processInfo.environment["EDITOR"]
            ?? ProcessInfo.processInfo.environment["VISUAL"]
            ?? "vi"
        let quoted = "'" + url.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return Shell.passthrough("/bin/sh", ["-c", "\(editor) \(quoted)"])
    }

    // MARK: - add

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Append text to today's note (or open $EDITOR with no argument)"
        )
        @OptionGroup var g: GlobalOptions
        @Argument(help: "Text to append; omit to read stdin, or open $EDITOR when stdin is a TTY") var text: String?

        func run() throws {
            wireOutput(g, command: "vorssaint note")
            try Note.ensureDirectory()
            let url = try Note.url(for: nil)

            let body: String
            if let text {
                body = text
            } else if stdinIsTTY {
                guard !Out.json && !Out.plain else {
                    Out.fail("usage", "note with no text is interactive — pass text when using --json/--plain",
                             exit: .usage)
                }
                let status = Note.openInEditor(url)
                guard status == 0 else { Out.fail("editor_failed", "$EDITOR exited with status \(status)") }
                struct Edited: Encodable { var path: String, edited: Bool }
                Out.emit(Edited(path: url.path, edited: true)) { "edited \(url.path)" }
                return
            } else {
                body = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
            }
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ValidationError("nothing to add — pass text or pipe stdin") }

            var contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if !contents.isEmpty && !contents.hasSuffix("\n") { contents += "\n" }
            contents += trimmed + "\n"
            do { try contents.write(to: url, atomically: true, encoding: .utf8) }
            catch { Out.fail("write_failed", "cannot write \(url.path): \(error.localizedDescription)") }

            struct R: Encodable { var path: String, name: String, appended: Int }
            let r = R(path: url.path, name: url.lastPathComponent, appended: trimmed.utf8.count)
            Out.emit(r) { "appended \(r.appended) bytes → \(r.path)" }
        }
    }

    // MARK: - list

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List notes, newest first")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint note list")
            struct Entry: Encodable { var name: String, path: String, bytes: Int, modified: String }
            let iso = ISO8601DateFormatter()
            let entries = Note.notes().map { url -> Entry in
                let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                return Entry(name: url.lastPathComponent, path: url.path, bytes: v?.fileSize ?? 0,
                             modified: iso.string(from: v?.contentModificationDate ?? .distantPast))
            }
            if Out.json { Out.emit(entries) { "" } }
            else if entries.isEmpty { print("no notes — `vorssaint note \"first thought\"`") }
            else {
                Out.table(["NOTE", "SIZE", "MODIFIED"], rows: entries.map {
                    [$0.name, fmtBytes(UInt64($0.bytes)), $0.modified]
                })
            }
        }
    }

    // MARK: - show

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print a note (default: today)")
        @OptionGroup var g: GlobalOptions
        @Argument(help: "Note name or 'today'") var name: String?
        func run() throws {
            wireOutput(g, command: "vorssaint note show")
            let url = try Note.url(for: name)
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                Out.fail("not_found", "no note at \(url.path) — create it with `vorssaint note \"…\"`", exit: .notFound)
            }
            struct R: Encodable { var name: String, path: String, content: String }
            Out.emit(R(name: url.lastPathComponent, path: url.path, content: contents)) { contents }
        }
    }

    // MARK: - edit

    struct Edit: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Open a note in $EDITOR")
        @OptionGroup var g: GlobalOptions
        @Argument(help: "Note name or 'today'") var name: String?
        func run() throws {
            wireOutput(g, command: "vorssaint note edit")
            guard !Out.json && !Out.plain else {
                Out.fail("usage", "note edit is interactive and cannot run with --json/--plain", exit: .usage)
            }
            try Note.ensureDirectory()
            let url = try Note.url(for: name)
            if !FileManager.default.fileExists(atPath: url.path) {
                try? "".write(to: url, atomically: true, encoding: .utf8)
            }
            let status = Note.openInEditor(url)
            guard status == 0 else { Out.fail("editor_failed", "$EDITOR exited with status \(status)") }
            struct Edited: Encodable { var path: String, edited: Bool }
            Out.emit(Edited(path: url.path, edited: true)) { "edited \(url.path)" }
        }
    }
}
