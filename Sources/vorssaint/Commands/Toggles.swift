// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation

// One-shot system toggles that the menu-bar app surfaces as quick actions.

struct Appearance: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "System appearance (dark/light)",
        subcommands: [Get.self, Dark.self, Light.self, Toggle.self],
        defaultSubcommand: Get.self
    )

    static func isDark() -> Bool {
        // AppleInterfaceStyle only exists in dark mode
        let r = Shell.run("/usr/bin/defaults", ["read", "-g", "AppleInterfaceStyle"])
        return r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "dark"
    }

    static func set(_ dark: Bool) -> Bool {
        let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)"
        let r = Shell.run("/usr/bin/osascript", ["-e", script])
        return r.status == 0
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show current appearance")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint appearance")
            let dark = Appearance.isDark()
            Out.emit(["mode": dark ? "dark" : "light"]) { dark ? "dark" : "light" }
        }
    }

    struct Dark: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Switch to dark mode")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint appearance dark")
            try Appearance.go(dark: true)
        }
    }
    struct Light: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Switch to light mode")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint appearance light")
            try Appearance.go(dark: false)
        }
    }
    private static func go(dark: Bool) throws {
        guard Appearance.set(dark) else {
            Out.fail("permission", "could not set appearance — grant Automation permission for System Events (run `vorssaint doctor`)", exit: .permission)
        }
        Out.emit(["mode": dark ? "dark" : "light"]) { "appearance → \(dark ? "dark" : "light")" }
    }

    struct Toggle: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Toggle dark/light")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint appearance toggle")
            try Appearance.go(dark: !Appearance.isDark())
        }
    }
}

struct DesktopIcons: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "desktop-icons",
        abstract: "Show/hide Finder desktop icons",
        subcommands: [Hide.self, Show.self, Toggle.self],
        defaultSubcommand: Toggle.self
    )

    static func apply(hidden: Bool) {
        _ = Shell.run("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", hidden ? "false" : "true"])
        _ = Shell.run("/usr/bin/killall", ["Finder"])
    }
    static func isHidden() -> Bool {
        let r = Shell.run("/usr/bin/defaults", ["read", "com.apple.finder", "CreateDesktop"])
        return r.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "0"
    }

    struct Hide: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Hide desktop icons")
        @OptionGroup var g: GlobalOptions
        func run() throws { wireOutput(g, command: "vorssaint desktop-icons hide"); DesktopIcons.apply(hidden: true); Out.emit(["hidden": true]) { "desktop icons hidden" } }
    }
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show desktop icons")
        @OptionGroup var g: GlobalOptions
        func run() throws { wireOutput(g, command: "vorssaint desktop-icons show"); DesktopIcons.apply(hidden: false); Out.emit(["hidden": false]) { "desktop icons shown" } }
    }
    struct Toggle: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Toggle desktop icons")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint desktop-icons")
            let h = !DesktopIcons.isHidden()
            DesktopIcons.apply(hidden: h)
            Out.emit(["hidden": h]) { h ? "desktop icons hidden" : "desktop icons shown" }
        }
    }
}

struct Spaces: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Mission Control Space ordering",
        subcommands: [LockOrder.self, UnlockOrder.self],
        defaultSubcommand: nil
    )

    static func apply(locked: Bool) {
        // mru-spaces = "automatically rearrange Spaces based on most recent use"
        _ = Shell.run("/usr/bin/defaults", ["write", "com.apple.dock", "mru-spaces", "-bool", locked ? "false" : "true"])
        _ = Shell.run("/usr/bin/killall", ["Dock"])
    }

    struct LockOrder: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "lock-order", abstract: "Keep Spaces in fixed order")
        @OptionGroup var g: GlobalOptions
        func run() throws { wireOutput(g, command: "vorssaint spaces lock-order"); Spaces.apply(locked: true); Out.emit(["fixed": true]) { "Spaces order locked (Dock restarted)" } }
    }
    struct UnlockOrder: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "unlock-order", abstract: "Restore macOS recent-use ordering")
        @OptionGroup var g: GlobalOptions
        func run() throws { wireOutput(g, command: "vorssaint spaces unlock-order"); Spaces.apply(locked: false); Out.emit(["fixed": false]) { "Spaces order unlocked (Dock restarted)" } }
    }
}

struct MouseCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mouse",
        abstract: "Mouse settings",
        subcommands: [Accel.self]
    )

    struct Accel: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "acceleration",
            abstract: "Pointer acceleration on/off (applies after re-login or mouse replug)",
            subcommands: [On.self, Off.self, Status.self],
            defaultSubcommand: Status.self
        )
        static func read() -> Double? {
            let r = Shell.run("/usr/bin/defaults", ["read", "-g", "com.apple.mouse.scaling"])
            return Double(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        struct On: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Restore default acceleration")
            @OptionGroup var g: GlobalOptions
            func run() throws {
                wireOutput(g, command: "vorssaint mouse acceleration on")
                _ = Shell.run("/usr/bin/defaults", ["write", "-g", "com.apple.mouse.scaling", "-float", "1.5"])
                Out.emit(["acceleration": true]) { "mouse acceleration on (re-login or replug to apply)" }
            }
        }
        struct Off: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Disable acceleration")
            @OptionGroup var g: GlobalOptions
            func run() throws {
                wireOutput(g, command: "vorssaint mouse acceleration off")
                _ = Shell.run("/usr/bin/defaults", ["write", "-g", "com.apple.mouse.scaling", "-float", "-1"])
                Out.emit(["acceleration": false]) { "mouse acceleration off (re-login or replug to apply)" }
            }
        }
        struct Status: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Show current tracking value")
            @OptionGroup var g: GlobalOptions
            func run() throws {
                wireOutput(g, command: "vorssaint mouse acceleration")
                let v = Accel.read()
                let on = (v ?? 1.5) >= 0
                struct R: Encodable { var scaling: Double?, acceleration: Bool }
                Out.emit(R(scaling: v, acceleration: on)) { "com.apple.mouse.scaling = \(v.map { String($0) } ?? "(unset)")  →  acceleration \(on ? "on" : "off")" }
            }
        }
    }
}

struct Bluetooth: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Bluetooth power (via blueutil)",
        discussion: "Requires `brew install blueutil` — checked by `vorssaint doctor`.",
        subcommands: [On.self, Off.self, StatusCmd.self],
        defaultSubcommand: StatusCmd.self,
        aliases: ["bt"]
    )

    static func blueutil() -> String? { Shell.which("blueutil") }

    struct On: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Power on")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint bluetooth on")
            guard let b = Bluetooth.blueutil() else { Out.fail("missing_dep", "blueutil not found — `brew install blueutil`", exit: .notFound) }
            let r = Shell.run(b, ["-p", "1"])
            guard r.status == 0 else { Out.fail("bt_failed", r.stderr) }
            Out.emit(["power": true]) { "bluetooth on" }
        }
    }
    struct Off: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Power off")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint bluetooth off")
            guard let b = Bluetooth.blueutil() else { Out.fail("missing_dep", "blueutil not found — `brew install blueutil`", exit: .notFound) }
            let r = Shell.run(b, ["-p", "0"])
            guard r.status == 0 else { Out.fail("bt_failed", r.stderr) }
            Out.emit(["power": false]) { "bluetooth off" }
        }
    }
    struct StatusCmd: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "status", abstract: "Show power state")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint bluetooth status")
            guard let b = Bluetooth.blueutil() else { Out.fail("missing_dep", "blueutil not found — `brew install blueutil`", exit: .notFound) }
            let r = Shell.run(b, ["-p"])
            let on = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
            Out.emit(["power": on]) { "bluetooth \(on ? "on" : "off")" }
        }
    }
}

struct Lock: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Lock the screen immediately")
    @OptionGroup var g: GlobalOptions
    func run() throws {
        wireOutput(g, command: "vorssaint lock")
        let cg = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        if FileManager.default.isExecutableFile(atPath: cg) {
            let r = Shell.run(cg, ["-suspend"])
            guard r.status == 0 else { Out.fail("lock_failed", r.stderr.isEmpty ? "CGSession failed" : r.stderr) }
            Out.emit(["locked": true]) { "screen locked" }
        } else {
            let r = Shell.run("/usr/bin/pmset", ["displaysleepnow"])
            guard r.status == 0 else { Out.fail("lock_failed", r.stderr) }
            Out.emit(["locked": true]) { "display slept (locks if a password is required)" }
        }
    }
}
