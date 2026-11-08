// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation

struct PortEntry: Encodable {
    var port: Int, pid: Int32, process: String, proto: String, address: String
}

struct Ports: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Find processes listening on network ports",
        subcommands: [List.self, Kill.self],
        defaultSubcommand: List.self,
        aliases: ["port"]
    )

    static func listeners() -> [PortEntry] {
        let r = Shell.run("/usr/sbin/lsof", ["-nP", "+c", "0", "-iTCP", "-iUDP", "-sTCP:LISTEN"])
        guard r.status == 0 else { return [] }
        var out: [PortEntry] = []
        for line in r.stdout.split(separator: "\n").dropFirst() {
            // COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard f.count >= 9, let pid = Int32(f[1]) else { continue }
            let proto = f[7]
            let addr = f[8]
            guard let colon = addr.lastIndex(of: ":"), let port = Int(addr[addr.index(after: colon)...]) else { continue }
            out.append(PortEntry(port: port, pid: pid, process: f[0], proto: proto,
                                 address: String(addr[..<colon])))
        }
        return out.sorted { $0.port < $1.port }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List listening TCP/UDP ports")
        @OptionGroup var g: GlobalOptions
        @Option(help: "Filter by port") var port: Int?
        func run() throws {
            wireOutput(g, command: "vorssaint ports list")
            var rows = listeners()
            if let port { rows = rows.filter { $0.port == port } }
            if Out.json { Out.emit(rows) { "" } }
            else {
                Out.table(["PORT", "PROTO", "PID", "PROCESS", "BIND"], rows: rows.map {
                    [String($0.port), $0.proto, String($0.pid), $0.process, $0.address]
                })
            }
        }
    }

    struct Kill: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Kill the process listening on a port")
        @OptionGroup var g: GlobalOptions
        @Argument(help: "Port number") var port: Int
        @Flag(name: .long, help: "SIGKILL instead of SIGTERM") var force = false
        @Flag(name: .long) var yes = false
        func run() throws {
            wireOutput(g, command: "vorssaint ports kill")
            let hits = listeners().filter { $0.port == port }
            guard !hits.isEmpty else { Out.fail("not_found", "nothing listening on port \(port)", exit: .notFound) }
            for h in hits {
                Out.confirm("Kill \(h.process) (pid \(h.pid)) on :\(port)?", yes: yes)
                let sig = force ? SIGKILL : SIGTERM
                guard kill(h.pid, sig) == 0 else {
                    Out.fail("kill_failed", "could not signal pid \(h.pid): \(String(cString: strerror(errno)))")
                }
            }
            struct KillResult: Encodable { var port: Int, pid: Int32, process: String }
            Out.emit(hits.map { KillResult(port: $0.port, pid: $0.pid, process: $0.process) }) {
                "killed " + hits.map { "\($0.process) (\($0.pid))" }.joined(separator: ", ")
            }
        }
    }
}
