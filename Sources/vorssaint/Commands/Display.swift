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
        subcommands: [List.self, Brightness.self],
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
                    Out.fail("unsupported", "brightness not settable on \(d.name) (external monitors need DDC — planned)")
                }
                struct R: Encodable { var display: String, percent: Int }
                Out.emit(R(display: d.name, percent: percent)) { "\(d.name) → \(percent)%" }
            }
        }
    }
}
