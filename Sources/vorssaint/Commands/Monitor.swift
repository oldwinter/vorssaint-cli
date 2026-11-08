// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation

struct Monitor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Live system metrics",
        discussion: "One-shot readings for CPU, memory, disk, network, battery and fans. Add --watch for a live TUI view, or use `vorssaint top`.",
        subcommands: [AllCmd.self, CPUCmd.self, MemCmd.self, DiskCmd.self, NetCmd.self, BatteryCmd.self, SensorsCmd.self],
        defaultSubcommand: AllCmd.self,
        aliases: ["mon", "stats"]
    )

    struct WatchOptions: ParsableArguments {
        @Flag(name: .long, help: "Live-updating view (TUI)")
        var watch = false
    }

    private static func watchLoop(_ render: @escaping () -> String) {
        TUI.run { render() }
    }

    struct AllCmd: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "all", abstract: "Everything, one screen")
        @OptionGroup var g: GlobalOptions
        @OptionGroup var w: WatchOptions
        func run() throws {
            wireOutput(g, command: "vorssaint monitor")
            if w.watch { Monitor.watchLoop { Self.render() }; return }
            Out.emit(Self.snapshot(), human: Self.human)
        }
        static func snapshot() -> Snapshot {
            let t0 = CPUTicks.sample(); Thread.sleep(forTimeInterval: 0.3); let t1 = CPUTicks.sample()
            let (busy, user, sys, idle) = CPUTicks.usage(between: t0, and: t1)
            let n0 = NetCounters.sample(); Thread.sleep(forTimeInterval: 0.5); let n1 = NetCounters.sample()
            return Snapshot(cpu: CPUData(usedPercent: busy, userPercent: user, systemPercent: sys, idlePercent: idle, loadAvg: Sys.loadAvg()),
                            mem: Memory.stats(), disk: Disk.stats(), net: NetData(interfaces: NetData.rates(n0, n1, dt: 0.5)),
                            battery: Battery.stats(), fans: SMC.fans(), uptimeSeconds: Sys.uptimeSeconds())
        }
        struct Snapshot: Encodable {
            var cpu: CPUData, mem: MemStats, disk: DiskStats?, net: NetData, battery: BatteryStats, fans: [SMC.Fan], uptimeSeconds: TimeInterval
        }
        static func human() -> String { render() }
        static func render() -> String {
            let s = snapshot()
            var o = ""
            let h = Sys.hostInfo()
            o += ANSI.bold("vorssaint monitor") + "  " + ANSI.dim("\(h.chip) · \(h.cores) cores · macOS \(h.os) · up \(fmtDuration(s.uptimeSeconds))") + "\n"
            o += String(format: "CPU   %5.1f%%  (user %.1f  sys %.1f)  load %.2f %.2f %.2f\n",
                        s.cpu.usedPercent, s.cpu.userPercent, s.cpu.systemPercent, s.cpu.loadAvg[0], s.cpu.loadAvg[1], s.cpu.loadAvg[2])
            o += String(format: "MEM   %5.1f%%  %@ / %@  (compressed %@, swap %@)\n",
                        s.mem.usedPercent, fmtBytes(s.mem.usedBytes), fmtBytes(s.mem.totalBytes),
                        fmtBytes(s.mem.compressedBytes), fmtBytes(s.mem.swapUsedBytes))
            if let d = s.disk {
                o += String(format: "DISK  %5.1f%%  %@ free of %@\n", d.usedPercent, fmtBytes(d.freeBytes), fmtBytes(d.totalBytes))
            }
            for i in s.net.interfaces where i.rxPerSec + i.txPerSec > 0 || i.name == "en0" {
                o += String(format: "NET   %-5@ ↓ %@/s  ↑ %@/s\n", i.name, fmtBytes(UInt64(max(0, i.rxPerSec))), fmtBytes(UInt64(max(0, i.txPerSec))))
            }
            if s.battery.present {
                let b = s.battery
                o += String(format: "BAT   %d%%  %@%@%@\n", b.percent,
                            b.charging ? "charging" : (b.onAC ? "on AC" : "on battery"),
                            b.cycleCount.map { "  \($0) cycles" } ?? "",
                            b.temperatureC.map { String(format: "  %.0f°C", $0) } ?? "")
            }
            for f in s.fans {
                o += String(format: "FAN%d  %5.0f rpm  (%.0f–%.0f)\n", f.index, f.rpm, f.minRpm, f.maxRpm)
            }
            return o
        }
    }

    struct CPUData: Encodable { var usedPercent, userPercent, systemPercent, idlePercent: Double; var loadAvg: [Double] }

    struct CPUCmd: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "cpu", abstract: "CPU usage (sampled over --interval seconds)")
        @OptionGroup var g: GlobalOptions
        @Option(help: "Sampling interval") var interval: Double = 0.5
        func run() throws {
            wireOutput(g, command: "vorssaint monitor cpu")
            let a = CPUTicks.sample(); Thread.sleep(forTimeInterval: interval); let b = CPUTicks.sample()
            let (busy, u, s, i) = CPUTicks.usage(between: a, and: b)
            Out.emit(CPUData(usedPercent: busy, userPercent: u, systemPercent: s, idlePercent: i, loadAvg: Sys.loadAvg())) {
                String(format: "%.1f%% used (user %.1f, sys %.1f, idle %.1f)  load %.2f %.2f %.2f",
                       busy, u, s, i, Sys.loadAvg()[0], Sys.loadAvg()[1], Sys.loadAvg()[2])
            }
        }
    }

    struct MemCmd: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "mem", abstract: "Memory usage")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint monitor mem")
            let m = Memory.stats()
            Out.emit(m) {
                String(format: "%.1f%% used — %@ of %@ (free %@, compressed %@, swap %@/%@)",
                       m.usedPercent, fmtBytes(m.usedBytes), fmtBytes(m.totalBytes), fmtBytes(m.freeBytes),
                       fmtBytes(m.compressedBytes), fmtBytes(m.swapUsedBytes), fmtBytes(m.swapTotalBytes))
            }
        }
    }

    struct DiskCmd: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "disk", abstract: "Disk usage for a mount point")
        @OptionGroup var g: GlobalOptions
        @Argument(help: "Mount path") var path: String = "/"
        func run() throws {
            wireOutput(g, command: "vorssaint monitor disk")
            guard let d = Disk.stats(path: path) else {
                Out.fail("not_found", "no filesystem at \(path)", exit: .notFound)
            }
            Out.emit(d) {
                String(format: "%.1f%% used — %@ free of %@ (%@)", d.usedPercent, fmtBytes(d.freeBytes), fmtBytes(d.totalBytes), d.mount)
            }
        }
    }

    struct IfaceRate: Encodable { var name: String; var rxPerSec: Double; var txPerSec: Double; var rxTotalBytes: UInt64; var txTotalBytes: UInt64 }
    struct NetData: Encodable {
        var interfaces: [IfaceRate]
        static func rates(_ a: [IfaceCounters], _ b: [IfaceCounters], dt: Double) -> [IfaceRate] {
            b.map { nb in
                let prev = a.first { $0.name == nb.name }
                return IfaceRate(name: nb.name,
                                 rxPerSec: Double(Int64(nb.rxBytes) - Int64(prev?.rxBytes ?? nb.rxBytes)) / dt,
                                 txPerSec: Double(Int64(nb.txBytes) - Int64(prev?.txBytes ?? nb.txBytes)) / dt,
                                 rxTotalBytes: nb.rxBytes, txTotalBytes: nb.txBytes)
            }
        }
    }

    struct NetCmd: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "net", abstract: "Network throughput (sampled over --interval seconds)")
        @OptionGroup var g: GlobalOptions
        @Option(help: "Sampling interval") var interval: Double = 1.0
        func run() throws {
            wireOutput(g, command: "vorssaint monitor net")
            let a = NetCounters.sample(); Thread.sleep(forTimeInterval: interval); let b = NetCounters.sample()
            let rates = NetData.rates(a, b, dt: interval)
            Out.emit(NetData(interfaces: rates)) {
                rates.filter { $0.rxPerSec + $0.txPerSec > 1 || $0.name == "en0" }
                    .map { String(format: "%-6@ ↓ %9@/s  ↑ %9@/s  (total ↓ %@ ↑ %@)", $0.name,
                                  fmtBytes(UInt64(max(0, $0.rxPerSec))), fmtBytes(UInt64(max(0, $0.txPerSec))),
                                  fmtBytes($0.rxTotalBytes), fmtBytes($0.txTotalBytes)) }
                    .joined(separator: "\n")
            }
        }
    }

    struct BatteryCmd: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "battery", abstract: "Battery state, cycles, temperature")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint monitor battery")
            let b = Battery.stats()
            guard b.present else { Out.fail("not_found", "no battery detected (desktop Mac?)", exit: .notFound) }
            Out.emit(b) {
                var s = "\(b.percent)% — \(b.charging ? "charging" : (b.onAC ? "on AC" : "on battery"))"
                if let c = b.cycleCount { s += ", \(c) cycles" }
                if let t = b.temperatureC { s += String(format: ", %.1f°C", t) }
                if let t = b.timeToEmptyMin { s += ", \(t / 60)h\(t % 60)m left" }
                return s
            }
        }
    }

    struct SensorsData: Encodable { var fans: [SMC.Fan]; var batteryTempC: Double? }
    struct SensorsCmd: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "sensors", abstract: "Fans and available temperatures")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint monitor sensors")
            let d = SensorsData(fans: SMC.fans(), batteryTempC: Battery.stats().temperatureC)
            Out.emit(d) {
                var s = ""
                for f in d.fans { s += String(format: "fan%d  %5.0f rpm (range %.0f–%.0f)\n", f.index, f.rpm, f.minRpm, f.maxRpm) }
                if let t = d.batteryTempC { s += String(format: "battery %.1f°C\n", t) }
                return s.isEmpty ? "no sensors readable (SMC unavailable)" : s.trimmingCharacters(in: .newlines)
            }
        }
    }
}
