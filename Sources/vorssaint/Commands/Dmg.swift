// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ArgumentParser
import Foundation

struct Dmg: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install an app from a .dmg (mount, copy, eject)",
        subcommands: [Install.self]
    )

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Copy the .app inside a disk image to /Applications",
            discussion: "Equivalent of the app's disk-image installer feature."
        )
        @OptionGroup var g: GlobalOptions
        @Argument(help: "Path to .dmg") var dmg: String
        @Option(help: "Destination directory") var to: String = "/Applications"
        @Flag(name: .long, help: "Remove the .dmg after install") var cleanup = false
        @Flag(name: .long) var yes = false
        func run() throws {
            wireOutput(g, command: "vorssaint dmg install")
            let path = (dmg as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else {
                Out.fail("not_found", "no file at \(path)", exit: .notFound)
            }
            let mount = NSTemporaryDirectory() + "vorssaint-dmg-\(UUID().uuidString.prefix(8))"
            let attach = Shell.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-mountpoint", mount, path])
            guard attach.status == 0 else { Out.fail("mount_failed", attach.stderr) }
            defer { _ = Shell.run("/usr/bin/hdiutil", ["detach", mount, "-quiet"]) }

            let apps = (try? FileManager.default.contentsOfDirectory(atPath: mount))?
                .filter { $0.hasSuffix(".app") } ?? []
            guard let appName = apps.first else { Out.fail("not_found", "no .app inside \(path)", exit: .notFound) }

            let dest = "\(to)/\(appName)"
            Out.confirm("Install \(appName) → \(dest)?", yes: yes)
            if FileManager.default.fileExists(atPath: dest) {
                do { try FileManager.default.removeItem(atPath: dest) }
                catch { Out.fail("install_failed", "cannot replace \(dest): \(error.localizedDescription)") }
            }
            let copy = Shell.run("/usr/bin/ditto", ["\(mount)/\(appName)", dest])
            guard copy.status == 0 else { Out.fail("copy_failed", copy.stderr) }
            if cleanup { try? FileManager.default.removeItem(atPath: path) }
            struct R: Encodable { var app: String, installedTo: String, dmgRemoved: Bool }
            Out.emit(R(app: appName, installedTo: dest, dmgRemoved: cleanup)) {
                "installed \(appName) → \(dest)" + (cleanup ? " (dmg removed)" : "")
            }
        }
    }
}
