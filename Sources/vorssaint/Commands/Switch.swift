// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ArgumentParser
import Foundation

struct Switch: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "TUI app switcher (↑↓ navigate, type to filter, Enter activates, q quits)",
        discussion: "Non-TTY: prints the same list for scripting (use `apps open <name>` to switch)."
    )
    @OptionGroup var g: GlobalOptions

    func run() throws {
        wireOutput(g, command: "vorssaint switch")
        guard stdoutIsTTY else {
            // scriptable fallback: emit the app list
            let rows = Apps.running().map(Apps.info)
            if Out.json { Out.emit(rows) { "" } }
            else { for r in rows { print("\(r.name)\t\(r.bundleID ?? "-")") } }
            return
        }

        var filter = ""
        var sel = 0
        var chosen: NSRunningApplication?

        func apps() -> [NSRunningApplication] {
            let all = Apps.running()
            guard !filter.isEmpty else { return all }
            return all.filter {
                ($0.localizedName ?? "").localizedCaseInsensitiveContains(filter)
                    || ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains(filter)
            }
        }

        func windows(of app: NSRunningApplication) -> [String] {
            WindowCmd.windows().filter { $0.pid == app.processIdentifier }
                .compactMap(\.title).filter { !$0.isEmpty }
        }

        let lastKey = TUI.runInteractive(refresh: 0.5) {
            let list = apps()
            var o = ANSI.bold("  vorssaint switch") + ANSI.dim("  ↑↓ move · Enter switch · type to filter · q quit") + "\n"
            if !filter.isEmpty { o += ANSI.cyan("  filter: \(filter)") + "\n" }
            o += "\n"
            for (i, a) in list.enumerated() {
                let name = a.localizedName ?? "?"
                let marker = a.isActive ? ANSI.green("●") : " "
                let wins = windows(of: a)
                let line = "  \(marker) \(name)" + ANSI.dim("  \(a.bundleIdentifier ?? "")\(wins.isEmpty ? "" : "  —  \(wins.prefix(2).joined(separator: " · "))")")
                o += (i == sel ? "\u{1B}[7m" + line.padding(toLength: 90, withPad: " ", startingAt: 0) + "\u{1B}[0m" : line) + "\n"
            }
            if list.isEmpty { o += ANSI.dim("  no matching apps") + "\n" }
            return o
        } onKey: { key in
            let list = apps()
            switch key {
            case .up: sel = max(0, sel - 1)
            case .down: sel = min(max(0, list.count - 1), sel + 1)
            case .enter:
                if !list.isEmpty { chosen = list[min(sel, list.count - 1)] }
                return false
            case .quit: return false
            case .char(let ch):
                if ch == "\u{7F}" { if !filter.isEmpty { filter.removeLast() } }
                else { filter.append(ch); sel = 0 }
            default: break
            }
            return true
        }

        if lastKey == .enter, let chosen {
            chosen.activate()
            struct R: Encodable { var activated: String, pid: Int32 }
            Out.emit(R(activated: chosen.localizedName ?? "?", pid: chosen.processIdentifier)) {
                "switched to \(chosen.localizedName ?? "?")"
            }
        }
    }
}
