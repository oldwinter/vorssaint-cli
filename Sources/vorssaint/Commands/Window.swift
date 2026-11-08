// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ArgumentParser
import Foundation

struct WindowCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "window",
        abstract: "Window listing and layout",
        subcommands: [List.self, Snap.self, Zoom.self],
        defaultSubcommand: List.self,
        aliases: ["win"]
    )

    struct WinInfo: Encodable {
        var owner: String, pid: Int32, title: String?, x: Int, y: Int, w: Int, h: Int, onScreen: Bool
    }

    static func windows() -> [WinInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { w in
            guard let owner = w[kCGWindowOwnerName as String] as? String,
                  let pid = w[kCGWindowOwnerPID as String] as? Int32,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            return WinInfo(owner: owner, pid: pid, title: w[kCGWindowName as String] as? String,
                           x: Int(b["X"] ?? 0), y: Int(b["Y"] ?? 0), w: Int(b["Width"] ?? 0), h: Int(b["Height"] ?? 0),
                           onScreen: (w[kCGWindowIsOnscreen as String] as? Bool) ?? true)
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List on-screen windows (titles need Screen Recording permission)")
        @OptionGroup var g: GlobalOptions
        @Option(help: "Filter by owner app name") var app: String?
        func run() throws {
            wireOutput(g, command: "vorssaint window list")
            var ws = WindowCmd.windows()
            if let app { ws = ws.filter { $0.owner.localizedCaseInsensitiveContains(app) } }
            if Out.json { Out.emit(ws) { "" } }
            else {
                Out.table(["APP", "TITLE", "GEOMETRY"], rows: ws.map {
                    [$0.owner, $0.title ?? ANSI.dim("(no title — grant Screen Recording)"), "\($0.w)×\($0.h) @\($0.x),\($0.y)"]
                })
            }
        }
    }

    struct Snap: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Snap a window into a layout (planned)")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint window snap")
            Out.notImplemented("window snap — needs Accessibility scripting (AX position/size)")
        }
    }

    struct Zoom: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Zoom/fill a window (planned)")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint window zoom")
            Out.notImplemented("window zoom")
        }
    }
}
