// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ArgumentParser
import Foundation

// Brightness uses the private DisplayServices framework via dlopen — the same
// mechanism open-source brightness tools use. Internal-Display control on
// Apple Silicon works; external monitors may report unsupported.

private typealias DSGetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
private typealias DSSetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

private enum DS {
    static let get: DSGetBrightness? = load("DisplayServicesGetBrightness")
    static let set: DSSetBrightness? = load("DisplayServicesSetBrightness")
    private static func load<T>(_ sym: String) -> T? {
        guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let p = dlsym(h, sym) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }
}

struct Display: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Displays and brightness",
        subcommands: [List.self, Brightness.self, Boost.self, DDC.self],
        defaultSubcommand: List.self
    )

    struct Info: Encodable {
        var id: UInt32, name: String, width: Int, height: Int, isMain: Bool, builtin: Bool
        var brightness: Float?
    }

    static func displays() -> [Info] {
        NSScreen.screens.map { s in
            let id = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? 0
            var bri: Float?
            if let get = DS.get {
                var v = Float(0)
                if get(id, &v) == 0 { bri = v }
            }
            return Info(id: id, name: s.localizedName,
                        width: Int(s.frame.width), height: Int(s.frame.height),
                        isMain: s == NSScreen.main, builtin: CGDisplayIsBuiltin(id) != 0,
                        brightness: bri)
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List connected displays")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint display list")
            let ds = Display.displays()
            if Out.json { Out.emit(ds) { "" } }
            else {
                Out.table(["ID", "NAME", "SIZE", "BRIGHT", "KIND"], rows: ds.map {
                    [String($0.id), $0.name + ($0.isMain ? " *" : ""), "\($0.width)×\($0.height)",
                     $0.brightness.map { String(format: "%.0f%%", $0 * 100) } ?? "-",
                     $0.builtin ? "builtin" : "external"]
                })
            }
        }
    }

    struct Brightness: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "brightness",
            abstract: "Get or set display brightness",
            subcommands: [Get.self, Set.self],
            defaultSubcommand: Get.self
        )

        static func resolve(_ query: String?) -> (id: UInt32, name: String)? {
            let ds = Display.displays()
            guard let query, !query.isEmpty else {
                return (ds.first(where: { $0.builtin }) ?? ds.first).map { ($0.id, $0.name) }
            }
            if let n = UInt32(query), let d = ds.first(where: { $0.id == n }) { return (d.id, d.name) }
            let q = query.lowercased()
            return ds.first(where: { $0.name.lowercased().contains(q) }).map { ($0.id, $0.name) }
        }

        struct Get: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Get brightness")
            @OptionGroup var g: GlobalOptions
            @Argument(help: "Display id or name; default = builtin") var display: String?
            func run() throws {
                wireOutput(g, command: "vorssaint display brightness")
                guard let d = Brightness.resolve(display) else { Out.fail("not_found", "no matching display", exit: .notFound) }
                guard let get = DS.get else { Out.fail("unsupported", "DisplayServices unavailable") }
                var v = Float(0)
                guard get(d.id, &v) == 0 else { Out.fail("unsupported", "brightness not readable on \(d.name)") }
                struct R: Encodable { var display: String, percent: Int }
                Out.emit(R(display: d.name, percent: Int((v * 100).rounded()))) { "\(d.name): \(Int((v * 100).rounded()))%" }
            }
        }

        struct Set: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Set brightness 0–100")
            @OptionGroup var g: GlobalOptions
            @Argument var percent: Int
            @Option(help: "Display id or name") var display: String?
            func run() throws {
                wireOutput(g, command: "vorssaint display brightness set")
                guard (0...100).contains(percent) else { throw ValidationError("percent must be 0–100") }
                guard let d = Brightness.resolve(display) else { Out.fail("not_found", "no matching display", exit: .notFound) }
                guard let set = DS.set else { Out.fail("unsupported", "DisplayServices unavailable") }
                guard set(d.id, Float(percent) / 100) == 0 else {
                    Out.fail("unsupported", "brightness not settable on \(d.name) (external monitors need `vorssaint display ddc`)")
                }
                struct R: Encodable { var display: String, percent: Int }
                Out.emit(R(display: d.name, percent: percent)) { "\(d.name) → \(percent)%" }
            }
        }
    }

    struct Boost: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "XDR extra brightness above the normal maximum",
            discussion: """
            Drives the private DisplayServices brightness setter above 1.0. Only
            XDR-capable built-in panels accept it; every other display reads back
            1.0 and the command fails with a clear error instead of pretending.
            The boost is reset by sleep, display changes, or --reset.

              vorssaint display boost                 # 1.2×
              vorssaint display boost --amount 1.5
              vorssaint display boost --reset
            """
        )
        @OptionGroup var g: GlobalOptions
        @Option(name: .long, help: "Boost multiplier 1.0–1.6") var amount: Double = 1.2
        @Option(help: "Display id or name; default builtin") var display: String?
        @Flag(name: .long, help: "Return to normal brightness (1.0)") var reset = false

        func run() throws {
            wireOutput(g, command: "vorssaint display boost")
            guard (1.0...1.6).contains(amount) else { throw ValidationError("--amount must be 1.0–1.6") }
            guard let d = Brightness.resolve(display) else { Out.fail("not_found", "no matching display", exit: .notFound) }
            guard let set = DS.set, let get = DS.get else {
                Out.fail("unsupported", "DisplayServices unavailable", exit: .notImplemented)
            }
            let target = Float(reset ? 1.0 : amount)
            guard set(d.id, target) == 0 else {
                Out.fail("unsupported", "\(d.name) rejected the brightness write", exit: .notImplemented)
            }
            var readBack = Float(0)
            guard get(d.id, &readBack) == 0 else {
                Out.fail("unsupported", "brightness not readable on \(d.name)", exit: .notImplemented)
            }
            if !reset, readBack <= 1.01 {
                Out.fail("unsupported",
                         "\(d.name) did not accept XDR boost (read back \(String(format: "%.2f", readBack))×) — only XDR-capable built-in displays support values above 1.0",
                         exit: .notImplemented)
            }
            struct R: Encodable { var display: String, multiplier: Double }
            let r = R(display: d.name, multiplier: Double(readBack))
            Out.emit(r) {
                reset ? "\(d.name) → normal brightness"
                      : String(format: "%@ → %.2f× extra brightness", d.name, r.multiplier)
            }
        }
    }

    struct DDC: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "ddc",
            abstract: "External-monitor brightness over DDC/CI",
            discussion: """
            DDC/CI needs a helper: `brew install ddcctl` (Intel) or
            `brew install m1ddc` (Apple Silicon). Native IOAVService control is
            private and unverified, so this command uses whichever helper exists.

              vorssaint display ddc             # helper + external display status
              vorssaint display ddc 40 --index 1
            """
        )
        @OptionGroup var g: GlobalOptions
        @Argument(help: "Brightness 0–100") var percent: Int?
        @Option(name: .long, help: "DDC display index passed to the helper") var index: Int = 1

        func run() throws {
            wireOutput(g, command: "vorssaint display ddc")
            let ddcctl = Shell.which("ddcctl")
            let m1ddc = Shell.which("m1ddc")
            guard let percent else {
                let externals = Display.displays().filter { !$0.builtin }
                struct R: Encodable { var ddcctl: String?, m1ddc: String?, externalDisplays: [Display.Info] }
                let r = R(ddcctl: ddcctl, m1ddc: m1ddc, externalDisplays: externals)
                if Out.json { Out.emit(r) { "" } }
                else {
                    print("ddcctl: \(ddcctl ?? "not installed")")
                    print("m1ddc:  \(m1ddc ?? "not installed")")
                    for d in externals { print("external: \(d.name) (id \(d.id))") }
                }
                return
            }
            guard (0...100).contains(percent) else { throw ValidationError("percent must be 0–100") }
            guard ddcctl != nil || m1ddc != nil else {
                Out.fail("not_implemented",
                         "DDC/CI needs `brew install ddcctl` (Intel) or `brew install m1ddc` (Apple Silicon); native IOAVService control is private and unverified",
                         exit: .notImplemented)
            }
            let r: ShellResult
            if let ddcctl {
                r = Shell.run(ddcctl, ["-d", String(index), "-b", String(percent)])
            } else {
                r = Shell.run(m1ddc!, ["display", String(index), "set", "brightness", String(percent)])
            }
            guard r.status == 0 else {
                let msg = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                Out.fail("ddc_failed", msg.isEmpty ? "DDC helper exited with status \(r.status)" : msg)
            }
            struct R: Encodable { var displayIndex: Int, percent: Int, tool: String }
            let tool = ddcctl != nil ? "ddcctl" : "m1ddc"
            Out.emit(R(displayIndex: index, percent: percent, tool: tool)) {
                "display \(index) brightness → \(percent)% (DDC/CI via \(tool))"
            }
        }
    }
}
