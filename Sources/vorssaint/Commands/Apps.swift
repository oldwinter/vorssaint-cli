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
        subcommands: [List.self, Quit.self, QuitAll.self, QuitOthers.self, Open.self],
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
}
