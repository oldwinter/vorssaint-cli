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

    static let presets: [String: (x: Double, y: Double, w: Double, h: Double)] = [
        "left": (0, 0, 0.5, 1), "right": (0.5, 0, 0.5, 1),
        "top": (0, 0, 1, 0.5), "bottom": (0, 0.5, 1, 0.5),
        "tl": (0, 0, 0.5, 0.5), "top-left": (0, 0, 0.5, 0.5),
        "tr": (0.5, 0, 0.5, 0.5), "top-right": (0.5, 0, 0.5, 0.5),
        "bl": (0, 0.5, 0.5, 0.5), "bottom-left": (0, 0.5, 0.5, 0.5),
        "br": (0.5, 0.5, 0.5, 0.5), "bottom-right": (0.5, 0.5, 0.5, 0.5),
        "first-third": (0, 0, 1.0 / 3, 1), "center-third": (1.0 / 3, 0, 1.0 / 3, 1), "last-third": (2.0 / 3, 0, 1.0 / 3, 1),
        "first-two-thirds": (0, 0, 2.0 / 3, 1), "last-two-thirds": (1.0 / 3, 0, 2.0 / 3, 1),
        "fill": (0, 0, 1, 1), "center": (0.125, 0.1, 0.75, 0.8),
    ]

    static func applyLayout(_ preset: (x: Double, y: Double, w: Double, h: Double), to app: NSRunningApplication) -> Bool {
        guard let win = AX.mainWindow(of: app),
              let pos = AX.getPoint(win, kAXPositionAttribute),
              let size = AX.getSize(win, kAXSizeAttribute) else { return false }
        let vf = AX.visibleFrameAX(containing: CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2))
        let target = CGRect(x: vf.origin.x + preset.x * vf.width, y: vf.origin.y + preset.y * vf.height,
                            width: preset.w * vf.width, height: preset.h * vf.height)
        _ = AX.setSize(win, target.size)
        _ = AX.setPosition(win, target.origin)
        return AX.setSize(win, target.size)
    }

    struct Snap: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Snap a window into a preset layout",
            discussion: """
            Presets: left right top bottom | tl tr bl br | first-third center-third last-third |
                     first-two-thirds last-two-thirds | fill center
            Default target: frontmost app. Needs Accessibility permission (`vorssaint doctor`).
            """
        )
        @OptionGroup var g: GlobalOptions
        @Argument(help: "Layout preset") var preset: String
        @Option(help: "Target app (default: frontmost)") var app: String?
        func run() throws {
            wireOutput(g, command: "vorssaint window snap")
            guard AX.trusted else { Out.fail("permission", "Accessibility permission required — grant it in System Settings → Privacy & Security → Accessibility", exit: .permission) }
            guard let p = WindowCmd.presets[preset] else {
                Out.fail("bad_preset", "unknown preset '\(preset)' — one of: \(WindowCmd.presets.keys.sorted().joined(separator: " "))", exit: .runtime)
            }
            let target: NSRunningApplication?
            if let app { target = Apps.match(app) } else { target = NSWorkspace.shared.frontmostApplication }
            guard let target else { Out.fail("not_found", "no running app matching '\(app ?? "frontmost")'", exit: .notFound) }
            guard WindowCmd.applyLayout(p, to: target) else {
                Out.fail("layout_failed", "could not resize \(target.localizedName ?? "app") — no snappable window (minimized? no windows?)")
            }
            struct R: Encodable { var app: String, preset: String }
            Out.emit(R(app: target.localizedName ?? "?", preset: preset)) { "\(target.localizedName ?? "window") → \(preset)" }
        }
    }

    struct Zoom: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Fill the screen without creating a new Space (same as `snap fill`)")
        @OptionGroup var g: GlobalOptions
        @Option(help: "Target app (default: frontmost)") var app: String?
        func run() throws {
            wireOutput(g, command: "vorssaint window zoom")
            guard AX.trusted else { Out.fail("permission", "Accessibility permission required", exit: .permission) }
            let target = app.flatMap { Apps.match($0) } ?? NSWorkspace.shared.frontmostApplication
            guard let target else { Out.fail("not_found", "no running app", exit: .notFound) }
            guard WindowCmd.applyLayout(WindowCmd.presets["fill"]!, to: target) else {
                Out.fail("layout_failed", "could not resize \(target.localizedName ?? "app")")
            }
            struct R: Encodable { var app: String, preset: String }
            Out.emit(R(app: target.localizedName ?? "?", preset: "fill")) { "\(target.localizedName ?? "window") → fill" }
        }
    }
}
