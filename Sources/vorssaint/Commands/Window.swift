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
        /// 1-based index into the app's AX window order — the `--index` value
        /// for `window snap`. Nil when the window couldn't be matched to an
        /// AX element (or no --app filter was given).
        var axIndex: Int?
    }

    static func windows() -> [WinInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { w in
            guard let owner = w[kCGWindowOwnerName as String] as? String,
                  let pid = w[kCGWindowOwnerPID as String] as? Int32,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            return WinInfo(owner: owner, pid: pid, title: w[kCGWindowName as String] as? String,
                           x: Int(b["X"] ?? 0), y: Int(b["Y"] ?? 0), w: Int(b["Width"] ?? 0), h: Int(b["Height"] ?? 0),
                           onScreen: (w[kCGWindowIsOnscreen as String] as? Bool) ?? true, axIndex: nil)
        }
    }

    /// A CG bounds dict and an AX frame describe the same window when their
    /// corners agree within 2pt (both use global top-left origin).
    private static func matches(_ w: WinInfo, _ f: CGRect) -> Bool {
        abs(f.origin.x - CGFloat(w.x)) < 2 && abs(f.origin.y - CGFloat(w.y)) < 2
            && abs(f.width - CGFloat(w.w)) < 2 && abs(f.height - CGFloat(w.h)) < 2
    }

    /// The app's AX windows paired with their frames, in AX order (frames
    /// that can't be read are dropped).
    private static func axWindowsWithFrames(of app: NSRunningApplication) -> [(win: AXUIElement, frame: CGRect)] {
        AX.windows(of: app).compactMap { w in AX.frame(of: w).map { (w, $0) } }
    }

    /// Fill `axIndex` for rows owned by apps matching `query` (same matching
    /// as `Apps.match`). Index n = nth row of `window list --app <query>`.
    static func annotateAXIndices(_ ws: inout [WinInfo], only query: String?) {
        guard let query, let app = Apps.match(query) else { return }
        var ax = axWindowsWithFrames(of: app)
        var n = 0
        for i in ws.indices where ws[i].pid == app.processIdentifier {
            if let k = ax.firstIndex(where: { matches(ws[i], $0.frame) }) {
                ax.remove(at: k)
                n += 1
                ws[i].axIndex = n
            }
        }
    }

    /// The app's AX windows in `window list` (CG front-to-back) order, so
    /// `--index n` selects the nth row of `window list --app <name>`.
    static func orderedWindows(of app: NSRunningApplication) -> [AXUIElement] {
        var ax = axWindowsWithFrames(of: app)
        var ordered: [AXUIElement] = []
        for w in windows() where w.pid == app.processIdentifier {
            if let k = ax.firstIndex(where: { matches(w, $0.frame) }) {
                ordered.append(ax.remove(at: k).win)
            }
        }
        return ordered + ax.map(\.win) // unlisted AX windows (offscreen etc.) go last
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List on-screen windows (titles need Screen Recording permission)")
        @OptionGroup var g: GlobalOptions
        @Option(help: "Filter by owner app name") var app: String?
        func run() throws {
            wireOutput(g, command: "vorssaint window list")
            var ws = WindowCmd.windows()
            if let app { ws = ws.filter { $0.owner.localizedCaseInsensitiveContains(app) } }
            WindowCmd.annotateAXIndices(&ws, only: app)
            if Out.json { Out.emit(ws) { "" } }
            else {
                Out.table(["IDX", "APP", "TITLE", "GEOMETRY"], rows: ws.map {
                    [$0.axIndex.map(String.init) ?? "-", $0.owner,
                     $0.title ?? ANSI.dim("(no title — grant Screen Recording)"),
                     "\($0.w)×\($0.h) @\($0.x),\($0.y)"]
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

    /// Rectangle-style `cycle` walks these layouts in order.
    static let cycleOrder = ["left", "center-third", "right"]

    /// Next layout in `cycleOrder` for a window whose current frame already
    /// sits on one of them (3pt tolerance); otherwise the first.
    static func nextCyclePreset(of win: AXUIElement, on screen: NSScreen) -> String {
        let vf = AX.visibleFrameAX(of: screen)
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 3 }
        if let cur = AX.frame(of: win),
           let i = cycleOrder.firstIndex(where: { name in
               let p = presets[name]!
               return near(cur.origin.x, vf.origin.x + p.x * vf.width)
                   && near(cur.origin.y, vf.origin.y + p.y * vf.height)
                   && near(cur.width, p.w * vf.width) && near(cur.height, p.h * vf.height)
           }) { return cycleOrder[(i + 1) % cycleOrder.count] }
        return cycleOrder[0]
    }

    /// `--display` target: a display ID or 1-based index from `display list`,
    /// or `next`/`prev` relative to the screen containing the window's center.
    static func resolveDisplay(_ spec: String, around win: AXUIElement) -> NSScreen {
        let screens = NSScreen.screens
        switch spec {
        case "next", "prev":
            let center = AX.frame(of: win).map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero
            let cur = AX.screen(containing: center)
            // Order displays spatially so next/prev follows their layout.
            let ordered = screens.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
            let i = ordered.firstIndex(of: cur) ?? 0
            return ordered[(i + (spec == "next" ? 1 : ordered.count - 1)) % ordered.count]
        default:
            guard let n = Int(spec) else {
                Out.fail("bad_display", "unknown display '\(spec)' — use an index or ID from `vorssaint display list`, or next/prev")
            }
            // Prefer a CGDirectDisplayID match, else the 1-based row number.
            if let s = screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == UInt32(n)
            }) { return s }
            if n >= 1, n <= screens.count { return screens[n - 1] }
            Out.fail("bad_display", "unknown display '\(spec)' — use an index or ID from `vorssaint display list`, or next/prev")
        }
    }

    static func applyLayout(_ preset: (x: Double, y: Double, w: Double, h: Double), to win: AXUIElement, on screen: NSScreen? = nil) -> Bool {
        guard let pos = AX.getPoint(win, kAXPositionAttribute),
              let size = AX.getSize(win, kAXSizeAttribute) else { return false }
        let vf = AX.visibleFrameAX(of: screen ?? AX.screen(containing: CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)))
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
                     first-two-thirds last-two-thirds | fill center | cycle (left → center-third → right)
            Default target: frontmost app. Needs Accessibility permission (`vorssaint doctor`).
            """
        )
        @OptionGroup var g: GlobalOptions
        @Argument(help: "Layout preset") var preset: String
        @Option(help: "Target app (default: frontmost)") var app: String?
        @Option(help: "Window index — nth row of `window list --app <name>` (default: main window)") var index: Int?
        @Option(help: "Target display: index or ID from `display list`, or next/prev (default: window's display)") var display: String?
        func run() throws {
            wireOutput(g, command: "vorssaint window snap")
            guard AX.trusted else { Out.fail("permission", "Accessibility permission required — grant it in System Settings → Privacy & Security → Accessibility", exit: .permission) }
            guard preset == "cycle" || WindowCmd.presets[preset] != nil else {
                Out.fail("bad_preset", "unknown preset '\(preset)' — one of: cycle \(WindowCmd.presets.keys.sorted().joined(separator: " "))", exit: .runtime)
            }
            let target: NSRunningApplication?
            if let app { target = Apps.match(app) } else { target = NSWorkspace.shared.frontmostApplication }
            guard let target else { Out.fail("not_found", "no running app matching '\(app ?? "frontmost")'", exit: .notFound) }
            if let index, index < 1 { Out.fail("bad_index", "--index is 1-based — run `vorssaint window list --app \(app ?? "<app>")` for indices") }
            let win: AXUIElement?
            if let index {
                let wins = WindowCmd.orderedWindows(of: target)
                win = index <= wins.count ? wins[index - 1] : nil
            } else { win = AX.mainWindow(of: target) }
            guard let win else {
                Out.fail("not_found", index == nil
                    ? "no snappable window on \(target.localizedName ?? "app")"
                    : "no window \(index!) on \(target.localizedName ?? "app") — run `vorssaint window list --app \(app ?? "<app>")`",
                    exit: .notFound)
            }
            let screen = display.map { WindowCmd.resolveDisplay($0, around: win) }
            let windowScreen = screen ?? AX.screen(containing: AX.frame(of: win).map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero)
            let name = preset == "cycle" ? WindowCmd.nextCyclePreset(of: win, on: windowScreen) : preset
            guard WindowCmd.applyLayout(WindowCmd.presets[name]!, to: win, on: screen) else {
                Out.fail("layout_failed", "could not resize \(target.localizedName ?? "app") — no snappable window (minimized? no windows?)")
            }
            let landed = AX.frame(of: win).map { AX.screen(containing: CGPoint(x: $0.midX, y: $0.midY)) }
            struct R: Encodable { var app: String, preset: String, display: String? }
            Out.emit(R(app: target.localizedName ?? "?", preset: name, display: landed?.localizedName)) {
                "\(target.localizedName ?? "window") → \(name)\(landed.map { " on \($0.localizedName)" } ?? "")"
            }
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
            guard let win = AX.mainWindow(of: target),
                  WindowCmd.applyLayout(WindowCmd.presets["fill"]!, to: win) else {
                Out.fail("layout_failed", "could not resize \(target.localizedName ?? "app")")
            }
            struct R: Encodable { var app: String, preset: String }
            Out.emit(R(app: target.localizedName ?? "?", preset: "fill")) { "\(target.localizedName ?? "window") → fill" }
        }
    }
}
