// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation

// Fan readout plus a carefully clamped SMC write path. Manual fan targets are
// not universally supported: Apple Silicon firmware often ignores F<n>Tg, in
// which case the command reports that instead of claiming success.

struct Fans: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Fan speeds and manual targets",
        discussion: """
        Reads fan RPM from SMC. `set` writes F<n>Tg (and the FS! forced bit when
        present), clamps to the fan's reported range, requires --yes, and
        verifies the write by reading the target back.

          vorssaint fans list
          vorssaint fans set 3000 --fan 0 --yes
          vorssaint fans auto --fan 0
        """,
        subcommands: [List.self, Set.self, Auto.self],
        defaultSubcommand: List.self,
        aliases: ["fan"]
    )

    static func all() -> [SMC.Fan] { SMC.fans() }

    /// FS! is a bitmask of fans under manual control (present on many Intel
    /// Macs). Best effort: absent on most Apple Silicon machines.
    static func setForcedBit(fan: Int, on: Bool) -> Bool {
        guard let (type, bytes) = SMC.readKey("FS! "), type.hasPrefix("ui"), bytes.count == 2 else { return false }
        var mask = bytes.reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
        let bit = UInt16(1) << UInt16(fan)
        if on { mask |= bit } else { mask &= ~bit }
        var be = mask.bigEndian
        return SMC.writeKey("FS! ", bytes: withUnsafeBytes(of: &be) { Array($0) })
    }

    static func targetKey(_ fan: Int) -> String { "F\(fan)Tg" }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show fan speeds and ranges")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint fans list")
            let fans = Fans.all()
            if Out.json { Out.emit(fans) { "" }; return }
            if fans.isEmpty {
                print("no fans readable — this Mac may have no fans or SMC access is unavailable")
                return
            }
            Out.table(["FAN", "RPM", "MIN", "MAX"], rows: fans.map {
                [String($0.index), String(format: "%.0f", $0.rpm),
                 String(format: "%.0f", $0.minRpm), String(format: "%.0f", $0.maxRpm)]
            })
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Set a manual fan target (requires --yes)")
        @OptionGroup var g: GlobalOptions
        @Argument(help: "Target RPM") var rpm: Int
        @Option(name: .long, help: "Fan index from `fans list`") var fan: Int = 0
        @Flag(name: .long, help: "Confirm the hardware write") var yes = false
        @Flag(name: .long, help: "Allow targets below the reported minimum") var force = false

        func run() throws {
            wireOutput(g, command: "vorssaint fans set")
            let fans = Fans.all()
            guard !fans.isEmpty else {
                Out.fail("not_found", "no SMC fans readable — manual fan control is unavailable on this Mac", exit: .notFound)
            }
            guard fans.indices.contains(fan) else {
                throw ValidationError("fan \(fan) does not exist (valid: 0–\(fans.count - 1))")
            }
            let f = fans[fan]
            let maxRpm = Int(f.maxRpm)
            let minRpm = Int(f.minRpm)
            guard rpm >= 0 else { throw ValidationError("rpm must be >= 0") }
            guard rpm <= maxRpm else {
                throw ValidationError("rpm \(rpm) exceeds fan \(fan)'s maximum of \(maxRpm)")
            }
            if rpm < minRpm && !force {
                throw ValidationError("rpm \(rpm) is below fan \(fan)'s minimum of \(minRpm); pass --force to override")
            }
            Out.confirm("Set fan \(fan) target to \(rpm) rpm?", yes: yes)

            let forced = Fans.setForcedBit(fan: fan, on: true)
            guard SMC.writeNumber(Fans.targetKey(fan), Double(rpm)) else {
                Out.fail("write_failed",
                         "SMC key \(Fans.targetKey(fan)) is not writable on this Mac — manual fan control is often unavailable on Apple Silicon",
                         exit: .notImplemented)
            }
            Thread.sleep(forTimeInterval: 1.0)
            guard let target = SMC.readFloat(Fans.targetKey(fan)) else {
                Out.fail("readback_failed", "wrote \(Fans.targetKey(fan)) but could not read it back")
            }
            guard abs(target - Double(rpm)) <= 2 else {
                Out.fail("write_ignored",
                         "SMC accepted \(rpm) rpm but reports \(Int(target)) rpm — firmware is managing this fan",
                         exit: .notImplemented)
            }
            let current = SMC.fans().first { $0.index == fan }?.rpm ?? f.rpm
            struct R: Encodable {
                var fan: Int, targetRpm: Int, currentRpm: Double
                var minRpm: Double, maxRpm: Double, forced: Bool
            }
            let r = R(fan: fan, targetRpm: rpm, currentRpm: current,
                      minRpm: f.minRpm, maxRpm: f.maxRpm, forced: forced)
            Out.emit(r) {
                String(format: "fan %d target → %d rpm (now %.0f, range %.0f–%.0f)%@",
                       fan, rpm, current, f.minRpm, f.maxRpm,
                       forced ? "" : " — FS! forced bit unavailable")
            }
        }
    }

    struct Auto: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Return a fan to automatic control")
        @OptionGroup var g: GlobalOptions
        @Argument(help: "Fan index from `fans list`") var fan: Int = 0
        func run() throws {
            wireOutput(g, command: "vorssaint fans auto")
            let fans = Fans.all()
            guard fans.indices.contains(fan) else {
                if fans.isEmpty {
                    Out.fail("not_found", "no SMC fans readable on this Mac", exit: .notFound)
                }
                throw ValidationError("fan \(fan) does not exist (valid: 0–\(fans.count - 1))")
            }
            let cleared = Fans.setForcedBit(fan: fan, on: false)
            // Writing 0 to the target is the conventional "auto" value; firmware
            // that ignores targets ignores this too, which the read-back shows.
            let wrote = SMC.writeNumber(Fans.targetKey(fan), 0)
            let target = SMC.readFloat(Fans.targetKey(fan))
            struct R: Encodable { var fan: Int, clearedForcedBit: Bool, targetWritten: Bool, targetRpm: Double? }
            let r = R(fan: fan, clearedForcedBit: cleared, targetWritten: wrote, targetRpm: target)
            Out.emit(r) {
                wrote ? "fan \(fan) returned to automatic control"
                      : "fan \(fan): target key not writable — firmware already manages this fan"
            }
        }
    }
}
