// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation

struct FeatureEntry: Encodable {
    let command: String
    let summary: String
    let status: String // "available" | "planned"
}

enum Catalog {
    static let entries: [FeatureEntry] = [
        .init(command: "monitor cpu|mem|disk|net|battery|sensors", summary: "Live system metrics", status: "available"),
        .init(command: "top", summary: "Full-screen TUI dashboard", status: "available"),
        .init(command: "volume get|set|mute|unmute|devices|output", summary: "Output volume & devices", status: "available"),
        .init(command: "mic get|set|mute|unmute", summary: "Input level & mute", status: "available"),
        .init(command: "volume route --app", summary: "Per-app volume / output routing", status: "planned"),
        .init(command: "apps list|quit|quit-all|quit-others|open", summary: "Running apps", status: "available"),
        .init(command: "switch", summary: "TUI app switcher", status: "available"),
        .init(command: "window list|snap|zoom", summary: "Window list & AX layout", status: "available"),
        .init(command: "ports list|kill", summary: "Listening ports → pids", status: "available"),
        .init(command: "brew list|search|info|install|uninstall|outdated|upgrade", summary: "Homebrew wrapper", status: "available"),
        .init(command: "clip get|set|clear", summary: "Clipboard read/write/clear", status: "available"),
        .init(command: "clip history", summary: "Clipboard history (needs daemon)", status: "planned"),
        .init(command: "url clean", summary: "Strip tracking params", status: "available"),
        .init(command: "awake", summary: "Keep Mac awake (--for/--while/--lid)", status: "available"),
        .init(command: "display list|brightness", summary: "Displays & brightness", status: "available"),
        .init(command: "display boost", summary: "XDR extra brightness", status: "planned"),
        .init(command: "appearance dark|light|toggle", summary: "System dark mode", status: "available"),
        .init(command: "desktop-icons hide|show|toggle", summary: "Finder desktop icons", status: "available"),
        .init(command: "spaces lock-order|unlock-order", summary: "Fix Space ordering", status: "available"),
        .init(command: "mouse acceleration on|off", summary: "Pointer acceleration", status: "available"),
        .init(command: "bluetooth on|off|status", summary: "Bluetooth power (blueutil)", status: "available"),
        .init(command: "lock", summary: "Lock the screen", status: "available"),
        .init(command: "trash list|empty", summary: "Trash inspection & empty", status: "available"),
        .init(command: "eject <vol|all>", summary: "Eject volumes", status: "available"),
        .init(command: "shot", summary: "Screenshots (screen/window/area)", status: "available"),
        .init(command: "record [out] --duration N", summary: "Screen recording (ScreenCaptureKit)", status: "available"),
        .init(command: "media info|convert|gif|compress", summary: "Local media tools (sips/ffmpeg)", status: "available"),
        .init(command: "clean scan|run", summary: "Cache/log cleaner (trashes)", status: "available"),
        .init(command: "agents", summary: "Claude/Codex/OpenCode local usage", status: "available"),
        .init(command: "apps uninstall", summary: "Uninstall + related files → Trash", status: "available"),
        .init(command: "ocr", summary: "Offline text recognition", status: "available"),
        .init(command: "color at|convert|pick", summary: "Screen color & conversions", status: "available"),
        .init(command: "net", summary: "Interfaces, IPs, throughput", status: "available"),
        .init(command: "speedtest", summary: "Apple networkQuality wrapper", status: "available"),
        .init(command: "snip list|add|expand|remove", summary: "Text snippets", status: "available"),
        .init(command: "dmg install", summary: "Install app from .dmg", status: "available"),
        .init(command: "downloads list|organize", summary: "Messaging downloads", status: "planned"),
        .init(command: "volume route --app", summary: "Per-app volume / routing", status: "planned"),
        .init(command: "doctor", summary: "Env & permission check", status: "available"),
        .init(command: "features", summary: "This catalog", status: "available"),
        .init(command: "settings path|export|import", summary: "Config management", status: "available"),
    ]
}

struct Features: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List every command with its implementation status",
        discussion: "Machine-readable capability catalog — the agent discovery endpoint."
    )

    @OptionGroup var g: GlobalOptions
    @Flag(name: .long, help: "Only show available commands") var availableOnly = false

    func run() throws {
        wireOutput(g, command: "vorssaint features")
        let rows = Catalog.entries.filter { !availableOnly || $0.status == "available" }
        if Out.json {
            Out.emit(rows) { "" }
        } else {
            Out.table(["COMMAND", "STATUS", "SUMMARY"],
                      rows: rows.map { [$0.command, $0.status == "available" ? ANSI.green("●") : ANSI.yellow("○"), $0.summary] })
        }
    }
}
