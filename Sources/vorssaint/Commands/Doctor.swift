// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ApplicationServices
import ArgumentParser
import CoreGraphics
import Foundation

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check environment, permissions and optional dependencies",
        discussion: "The agent self-diagnosis endpoint: what's available, what's missing, what to grant."
    )
    @OptionGroup var g: GlobalOptions

    struct Check: Encodable {
        var name: String, status: String, detail: String
        static func ok(_ n: String, _ d: String) -> Check { Check(name: n, status: "ok", detail: d) }
        static func warn(_ n: String, _ d: String) -> Check { Check(name: n, status: "warn", detail: d) }
        static func missing(_ n: String, _ d: String) -> Check { Check(name: n, status: "missing", detail: d) }
    }

    func run() throws {
        wireOutput(g, command: "vorssaint doctor")
        var checks: [Check] = []

        let v = ProcessInfo.processInfo.operatingSystemVersion
        let mac = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        checks.append(v.majorVersion >= 14 ? .ok("macos", mac) : .warn("macos", "\(mac) — macOS 14+ recommended"))

        checks.append(.ok("arch", Sys.hostInfo().chip))

        // screen recording: try a 1px capture
        let canCapture = CGWindowListCreateImage(CGRect(x: 0, y: 0, width: 1, height: 1),
                                                 .optionOnScreenOnly, kCGNullWindowID, []) != nil
        checks.append(canCapture
            ? .ok("screen-recording", "granted — shot/ocr/color/window titles work")
            : .warn("screen-recording", "not granted — `shot --window`, `ocr --screen`, `color at`, window titles will fail. Grant in System Settings → Privacy & Security → Screen Recording"))

        checks.append(AXIsProcessTrusted()
            ? .ok("accessibility", "granted")
            : .warn("accessibility", "not granted — needed by future window-layout commands"))

        // Full disk access probe: TCC-protected dir
        let fda = FileManager.default.isReadableFile(atPath: NSHomeDirectory() + "/Library/Application Support/com.apple.TCC")
        checks.append(fda ? .ok("full-disk-access", "granted") : .warn("full-disk-access", "not granted — only needed for future cleaner/features"))

        for (name, bins) in [("brew", ["brew"]), ("blueutil", ["blueutil"]), ("ffmpeg", ["ffmpeg"]), ("mas", ["mas"])] {
            if let path = bins.compactMap({ Shell.which($0) }).first {
                checks.append(.ok(name, path))
            } else {
                checks.append(.missing(name, "optional — enables \(name == "brew" ? "brew commands" : name == "blueutil" ? "bluetooth" : name == "ffmpeg" ? "future media commands" : "Mac App Store updates")"))
            }
        }

        checks.append(FileManager.default.isExecutableFile(atPath: "/usr/bin/networkQuality")
            ? .ok("networkquality", "/usr/bin/networkQuality — speedtest works")
            : .missing("networkquality", "speedtest unavailable"))

        let fans = SMC.fans()
        checks.append(fans.isEmpty ? .warn("smc", "no SMC fans readable") : .ok("smc", "\(fans.count) fan(s) readable"))

        let fails = checks.filter { $0.status == "warn" }.count

        if Out.json { Out.emit(checks) { "" } }
        else {
            for c in checks {
                let icon = c.status == "ok" ? ANSI.green("✓") : c.status == "warn" ? ANSI.yellow("!") : ANSI.dim("○")
                print("\(icon) \(ANSI.bold(c.name))  \(c.detail)")
            }
            print(ANSI.dim("\n\(fails) warning(s) — most commands still work without these"))
        }
    }
}
