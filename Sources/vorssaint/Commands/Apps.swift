// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ArgumentParser
import Foundation

struct AppInfo: Encodable {
    var pid: Int32, name: String, bundleID: String?, active: Bool, hidden: Bool, terminated: Bool
}

struct Apps: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List, quit and open apps",
        subcommands: [List.self, Quit.self, QuitAll.self, QuitOthers.self, Open.self, Uninstall.self],
        defaultSubcommand: List.self,
        aliases: ["app"]
    )

    static func running() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    static func info(_ a: NSRunningApplication) -> AppInfo {
        AppInfo(pid: a.processIdentifier, name: a.localizedName ?? "?",
                bundleID: a.bundleIdentifier, active: a.isActive, hidden: a.isHidden,
                terminated: a.isTerminated)
    }

    static func match(_ query: String) -> NSRunningApplication? {
        if let pid = Int32(query), let a = NSRunningApplication(processIdentifier: pid) { return a }
        let q = query.lowercased()
        return running().first { $0.bundleIdentifier?.lowercased() == q }
            ?? running().first { $0.localizedName?.lowercased() == q }
            ?? running().first { $0.localizedName?.lowercased().contains(q) ?? false }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List running regular apps")
        @OptionGroup var g: GlobalOptions
        @Flag(name: .long, help: "Include background/agent apps") var all = false
        func run() throws {
            wireOutput(g, command: "vorssaint apps list")
            let apps = (all ? NSWorkspace.shared.runningApplications : running()).sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
            let rows = apps.map(info)
            if Out.json { Out.emit(rows) { "" } }
            else {
                Out.table(["PID", "APP", "BUNDLE ID", "STATE"], rows: rows.map {
                    [String($0.pid), $0.name, $0.bundleID ?? "-", $0.active ? "frontmost" : ($0.hidden ? "hidden" : "open")]
                })
            }
        }
    }

    struct Quit: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Quit one app (name, bundle id, or pid)")
        @OptionGroup var g: GlobalOptions
        @Argument var app: String
        @Flag(name: .long, help: "Force quit") var force = false
        @Flag(name: .long) var yes = false
        func run() throws {
            wireOutput(g, command: "vorssaint apps quit")
            guard let a = match(app) else { Out.fail("not_found", "no running app matching '\(app)'", exit: .notFound) }
            Out.confirm("Quit \(a.localizedName ?? app) (pid \(a.processIdentifier))?", yes: yes)
            let ok = force ? a.forceTerminate() : a.terminate()
            guard ok else { Out.fail("quit_failed", "\(a.localizedName ?? app) refused to quit (try --force)") }
            struct QuitResult: Encodable { var quit: String, pid: Int32 }
            Out.emit(QuitResult(quit: a.localizedName ?? app, pid: a.processIdentifier)) { "quit \(a.localizedName ?? app)" }
        }
    }

    struct QuitAll: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Quit every regular app (except Finder and this terminal)")
        @OptionGroup var g: GlobalOptions
        @Flag(name: .long) var yes = false
        @Flag(name: .long) var force = false
        func run() throws {
            wireOutput(g, command: "vorssaint apps quit-all")
            let keep = Set(["com.apple.finder"]) + [Bundle.main.bundleIdentifier].compactMap { $0 }
            let targets = running().filter { !keep.contains($0.bundleIdentifier ?? "") && $0.processIdentifier != getpid() && $0.processIdentifier != getppid() }
            Out.confirm("Quit \(targets.count) apps?", yes: yes)
            var quit: [String] = [], failed: [String] = []
            for a in targets {
                if force ? a.forceTerminate() : a.terminate() { quit.append(a.localizedName ?? "?") } else { failed.append(a.localizedName ?? "?") }
            }
            Out.emit(["quit": quit, "failed": failed] as [String: [String]]) {
                "quit \(quit.count) apps" + (failed.isEmpty ? "" : " — failed: \(failed.joined(separator: ", "))")
            }
        }
    }

    struct QuitOthers: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Quit every app except the frontmost")
        @OptionGroup var g: GlobalOptions
        @Flag(name: .long) var yes = false
        func run() throws {
            wireOutput(g, command: "vorssaint apps quit-others")
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let targets = running().filter { $0.processIdentifier != front && $0.processIdentifier != getpid() }
                .filter { $0.bundleIdentifier != "com.apple.finder" }
            Out.confirm("Quit \(targets.count) background apps?", yes: yes)
            var quit: [String] = [], failed: [String] = []
            for a in targets { if a.terminate() { quit.append(a.localizedName ?? "?") } else { failed.append(a.localizedName ?? "?") } }
            Out.emit(["quit": quit, "failed": failed] as [String: [String]]) {
                "quit \(quit.count) apps" + (failed.isEmpty ? "" : " — failed: \(failed.joined(separator: ", "))")
            }
        }
    }

    struct Open: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Launch or focus an app")
        @OptionGroup var g: GlobalOptions
        @Argument var app: String
        func run() throws {
            wireOutput(g, command: "vorssaint apps open")
            if let a = match(app) { // already running → activate
                a.activate()
                Out.emit(["activated": a.localizedName ?? app]) { "activated \(a.localizedName ?? app)" }
                return
            }
            struct OpenResult: Encodable { var opened: String }
            // try open by name in /Applications and ~/Applications
            let candidates = ["/Applications/\(app).app", "\(NSHomeDirectory())/Applications/\(app).app"]
            if let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
                let url = URL(fileURLWithPath: path)
                let sem = DispatchSemaphore(value: 0)
                nonisolated(unsafe) var opened = false
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, err in
                    opened = err == nil; sem.signal()
                }
                _ = sem.wait(timeout: .now() + 15)
                guard opened else { Out.fail("open_failed", "could not open \(path)") }
                Out.emit(OpenResult(opened: path)) { "opened \(app)" }
            } else {
                Out.fail("not_found", "no app named '\(app)' in /Applications or running", exit: .notFound)
            }
        }
    }

    struct Related: Encodable { var path: String, kind: String, confidence: String, bytes: Int64 }

    /// How a filesystem entry was matched to an app. Raw values appear in the
    /// `CONFIDENCE` column and in `--json` output so users can review a
    /// dry-run before committing to `--yes`.
    enum MatchRule: String {
        case app = "app"                       // the .app bundle itself
        case bundleID = "bundle-id"            // exact bundle id
        case bundleIDPrefix = "bundle-id-prefix" // bundle id + "." suffix, or group.<bundle-id>
        case name = "name"                     // exact app name
        case nameBoundary = "name-boundary"    // app name delimited by "." boundaries
    }

    /// Match one directory entry against the app. Deliberately never uses a
    /// bare substring test: uninstalling "Vorssaint" must not claim
    /// `vorssaint-cli` caches, and "Arc" must not claim `com.example.arcade`.
    static func matchRule(entry: String, appName: String, bundleID: String?) -> MatchRule? {
        let e = entry.lowercased()
        if let bid = bundleID?.lowercased(), !bid.isEmpty {
            if e == bid { return .bundleID }
            if e.hasPrefix(bid + ".") { return .bundleIDPrefix }
            // Group Containers are named group.<bundle-id>[.<suffix>].
            if e.hasSuffix("." + bid) || e.contains("." + bid + ".") { return .bundleIDPrefix }
        }
        let name = appName.lowercased()
        guard !name.isEmpty else { return nil }
        if e == name { return .name }
        if e.hasPrefix(name + ".") || e.hasSuffix("." + name) || e.contains("." + name + ".") {
            return .nameBoundary
        }
        return nil
    }

    static func relatedFiles(appName: String, bundleID: String?,
                             home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> [Related] {
        let fm = FileManager.default
        var candidates: [(path: String, kind: String, rule: MatchRule)] = []
        let dirs = [
            "Library/Application Support", "Library/Caches", "Library/Logs",
            "Library/HTTPStorages", "Library/WebKit", "Library/Containers",
            "Library/Group Containers", "Library/Saved Application State",
            "Library/Preferences", "Library/LaunchAgents",
        ]
        for dir in dirs {
            let base = home + "/" + dir
            guard let entries = try? fm.contentsOfDirectory(atPath: base) else { continue }
            for e in entries {
                guard let rule = matchRule(entry: e, appName: appName, bundleID: bundleID) else { continue }
                candidates.append((base + "/" + e, dir.replacingOccurrences(of: "Library/", with: ""), rule))
            }
        }
        // dedupe, size up
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.path).inserted }.map { c in
            var bytes: Int64 = (try? fm.allocatedSizeOfDirectory(at: URL(fileURLWithPath: c.path))) ?? 0
            if bytes == 0, let a = try? fm.attributesOfItem(atPath: c.path) { bytes = (a[.size] as? Int64) ?? 0 }
            return Related(path: c.path, kind: c.kind, confidence: c.rule.rawValue, bytes: bytes)
        }.sorted { $0.bytes > $1.bytes }
    }

    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Uninstall an app and show related files (moves to Trash)",
            discussion: """
            Finds the .app plus caches, preferences, containers and support dirs, then moves everything to the Trash.
            Related files are matched by bundle id (exact or prefix) and by app-name boundaries — never by bare
            substring — so "Vorssaint" does not claim "vorssaint-cli" data and "Arc" does not claim "arcade".
            Each row's CONFIDENCE column names the rule that matched it; review with --dry-run first.
            """
        )
        @OptionGroup var g: GlobalOptions
        @Argument(help: "App name") var app: String
        @Flag(name: .long, help: "Only remove the .app, keep user data (default: include matched data)") var appOnly = false
        @Flag(name: .long) var dryRun = false
        @Flag(name: .long) var yes = false
        func run() throws {
            wireOutput(g, command: "vorssaint apps uninstall")
            // resolve the .app bundle
            let fm = FileManager.default
            var appPath: String?
            var bundleID: String?
            for dir in ["/Applications", "\(NSHomeDirectory())/Applications", "/System/Applications"] {
                guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
                if let hit = entries.first(where: {
                    $0.hasSuffix(".app") && $0.dropLast(4).lowercased() == app.lowercased()
                }) ?? entries.first(where: {
                    $0.hasSuffix(".app") && $0.lowercased().contains(app.lowercased())
                }) {
                    appPath = dir + "/" + hit
                    bundleID = Bundle(path: appPath!)?.bundleIdentifier
                    break
                }
            }
            guard let appPath else { Out.fail("not_found", "no .app matching '\(app)'", exit: .notFound) }
            let displayName = URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent

            var targets: [Related] = []
            let appSize = (try? fm.allocatedSizeOfDirectory(at: URL(fileURLWithPath: appPath))) ?? 0
            targets.append(Related(path: appPath, kind: "app", confidence: Apps.MatchRule.app.rawValue, bytes: appSize))
            if !appOnly { targets += Apps.relatedFiles(appName: displayName, bundleID: bundleID) }

            func printTable() {
                print(ANSI.bold("\(displayName)") + (bundleID.map { ANSI.dim("  \($0)") } ?? ""))
                Out.table(["SIZE", "KIND", "CONFIDENCE", "PATH"], rows: targets.map {
                    [fmtBytes(UInt64($0.bytes)), $0.kind, $0.confidence, $0.path]
                })
            }
            if dryRun {
                // Keep --json machine-readable: one envelope carrying every
                // row (with its match rule) instead of a table + JSON mix.
                struct R: Encodable { var dryRun: Bool, wouldTrash: Int, bytes: Int64, items: [Related] }
                let summary = R(dryRun: true, wouldTrash: targets.count,
                                bytes: targets.reduce(0) { $0 + $1.bytes }, items: targets)
                if Out.json { Out.emit(summary) { "" } }
                else { printTable(); print("--dry-run: nothing moved") }
                return
            }
            if Out.json { Out.emit(targets) { "" } } else { printTable() }
            Out.confirm("Move \(targets.count) items (\(fmtBytes(UInt64(targets.reduce(0) { $0 + $1.bytes })))) to Trash?", yes: yes)
            // quit the app first if running
            if let running = Apps.match(displayName) { _ = running.terminate() }
            var trashed = 0, failed: [String] = []
            for t in targets {
                do { try fm.trashItem(at: URL(fileURLWithPath: t.path), resultingItemURL: nil); trashed += 1 }
                catch { failed.append(t.path) }
            }
            struct R: Encodable { var trashed: Int, failed: [String] }
            Out.emit(R(trashed: trashed, failed: failed)) {
                "trashed \(trashed) items" + (failed.isEmpty ? "" : " — failed: \(failed.joined(separator: ", "))")
            }
        }
    }
}
