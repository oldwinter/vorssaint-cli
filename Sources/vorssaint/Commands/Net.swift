// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation

struct Net: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Local IPs and interface throughput",
        subcommands: [IP.self, Rates.self],
        defaultSubcommand: IP.self
    )

    struct IP: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "ip", abstract: "Show local (and --public) IP addresses")
        @OptionGroup var g: GlobalOptions
        @Flag(name: .long, help: "Also fetch public IP via api.ipify.org") var public_ = false
        func run() throws {
            wireOutput(g, command: "vorssaint net ip")
            struct Addr: Encodable { var interface: String, family: String, address: String }
            struct R: Encodable { var local: [Addr], publicIP: String? }
            let local = NetCounters.addresses().map { Addr(interface: $0.name, family: $0.family, address: $0.addr) }
            var pub: String?
            if public_ {
                if let url = URL(string: "https://api.ipify.org"),
                   let s = try? String(contentsOf: url, encoding: .utf8) {
                    pub = s.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            let r = R(local: local, publicIP: pub)
            if Out.json { Out.emit(r) { "" } }
            else {
                for a in local { print("\(a.interface)\t\(a.family)\t\(a.address)") }
                if let pub { print("public\tipv4\t\(pub)") }
            }
        }
    }

    struct Rates: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Per-interface throughput")
        @OptionGroup var g: GlobalOptions
        @Option var interval: Double = 1.0
        func run() throws {
            wireOutput(g, command: "vorssaint net rates")
            let a = NetCounters.sample(); Thread.sleep(forTimeInterval: interval); let b = NetCounters.sample()
            let rates = Monitor.NetData.rates(a, b, dt: interval)
            Out.emit(rates) {
                rates.map { String(format: "%-6@ ↓ %9@/s  ↑ %9@/s", $0.name,
                                   fmtBytes(UInt64(max(0, $0.rxPerSec))), fmtBytes(UInt64(max(0, $0.txPerSec)))) }
                    .joined(separator: "\n")
            }
        }
    }
}

struct Speedtest: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "speedtest",
        abstract: "Run Apple's networkQuality speed test",
        discussion: "Wraps /usr/bin/networkQuality (macOS 12+). Takes ~15s."
    )
    @OptionGroup var g: GlobalOptions
    @Flag(name: .long, help: "Sequential (not parallel) streams") var sequential = false

    struct Result: Encodable {
        var uplinkMbps: Double?, downlinkMbps: Double?, responsivenessRPM: Int?
        var raw: String
    }

    func run() throws {
        wireOutput(g, command: "vorssaint speedtest")
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/networkQuality") else {
            Out.fail("not_found", "networkQuality not found (macOS 12+ required)", exit: .notFound)
        }
        var args = ["-s"]
        if !sequential { args = [] }
        let r = Shell.run("/usr/bin/networkQuality", args)
        let text = r.stdout + r.stderr
        guard r.status == 0 else { Out.fail("speedtest_failed", text.trimmingCharacters(in: .whitespacesAndNewlines)) }

        func parseMbps(_ label: String) -> Double? {
            for line in text.split(separator: "\n") where line.contains(label) {
                for tok in line.split(whereSeparator: \.isWhitespace) {
                    if let v = Double(tok.replacingOccurrences(of: ",", with: "")) { return v }
                }
            }
            return nil
        }
        var rpm: Int?
        for line in text.split(separator: "\n") where line.lowercased().contains("responsiveness") {
            rpm = line.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }.first
        }
        let res = Result(uplinkMbps: parseMbps("Uplink"), downlinkMbps: parseMbps("Downlink"), responsivenessRPM: rpm, raw: text.trimmingCharacters(in: .whitespacesAndNewlines))
        if Out.json { Out.emit(res) { "" } }
        else { print(res.raw) }
    }
}
