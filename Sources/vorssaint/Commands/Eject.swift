// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation

struct Eject: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Eject disk images and volumes",
        subcommands: [Volume_.self, All.self, ListVols.self],
        defaultSubcommand: ListVols.self
    )

    static func volumes() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes"))?
            .filter { $0 != "Macintosh HD" && !$0.hasPrefix(".") } ?? []
    }

    struct ListVols: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List mounted volumes")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint eject list")
            let vs = Eject.volumes()
            Out.emit(vs) { vs.isEmpty ? "no external volumes" : vs.joined(separator: "\n") }
        }
    }

    struct Volume_: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "volume", abstract: "Eject one volume by name")
        @OptionGroup var g: GlobalOptions
        @Argument var name: String
        @Flag(name: .long) var yes = false
        func run() throws {
            wireOutput(g, command: "vorssaint eject volume")
            let vs = Eject.volumes()
            guard let match = vs.first(where: { $0.lowercased() == name.lowercased() })
                    ?? vs.first(where: { $0.lowercased().contains(name.lowercased()) }) else {
                Out.fail("not_found", "no volume matching '\(name)' — see `vorssaint eject list`", exit: .notFound)
            }
            Out.confirm("Eject /Volumes/\(match)?", yes: yes)
            let r = Shell.run("/usr/sbin/diskutil", ["eject", "/Volumes/\(match)"])
            guard r.status == 0 else { Out.fail("eject_failed", r.stderr.isEmpty ? r.stdout : r.stderr) }
            Out.emit(["ejected": match]) { "ejected \(match)" }
        }
    }

    struct All: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Eject all external volumes")
        @OptionGroup var g: GlobalOptions
        @Flag(name: .long) var yes = false
        func run() throws {
            wireOutput(g, command: "vorssaint eject all")
            let vs = Eject.volumes()
            if vs.isEmpty { Out.emit([String]()) { "no external volumes" }; return }
            Out.confirm("Eject \(vs.count) volumes: \(vs.joined(separator: ", "))?", yes: yes)
            var ok: [String] = [], failed: [String] = []
            for v in vs {
                if Shell.run("/usr/sbin/diskutil", ["eject", "/Volumes/\(v)"]).status == 0 { ok.append(v) } else { failed.append(v) }
            }
            Out.emit(["ejected": ok, "failed": failed] as [String: [String]]) {
                "ejected \(ok.count)" + (failed.isEmpty ? "" : " — failed: \(failed.joined(separator: ", "))")
            }
        }
    }
}
