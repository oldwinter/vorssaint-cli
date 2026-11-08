// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation

struct Eject: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Eject disk images and volumes",
        subcommands: [Volume_.self, All.self, ListVols.self],
        defaultSubcommand: ListVols.self
    )

    struct Vol: Encodable { var name: String, ejectable: Bool }

    static func volumes() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes"))?
            .filter { $0 != "Macintosh HD" && !$0.hasPrefix(".") } ?? []
    }

    /// `diskutil info -plist` says whether a volume may be ejected. Internal
    /// volumes (Data, Time Machine destinations, recovery) report
    /// `Ejectable = false`; on failure we conservatively return false.
    static func isEjectable(_ name: String) -> Bool {
        let r = Shell.run("/usr/sbin/diskutil", ["info", "-plist", "/Volumes/\(name)"])
        guard r.status == 0,
              let dict = try? PropertyListSerialization.propertyList(
                  from: Data(r.stdout.utf8), options: [], format: nil) as? [String: Any]
        else { return false }
        if let ejectable = dict["Ejectable"] as? Bool { return ejectable }
        if let location = dict["DeviceLocation"] as? String { return location == "External" }
        return false
    }

    /// Mounted volumes with their ejectable flag, ejectable first.
    static func vols() -> [Vol] {
        volumes().map { Vol(name: $0, ejectable: isEjectable($0)) }
            .sorted { $0.ejectable != $1.ejectable ? $0.ejectable : $0.name < $1.name }
    }

    struct ListVols: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List mounted volumes")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint eject list")
            let vs = Eject.vols()
            if Out.json {
                Out.emit(vs) { "" }
            } else if vs.isEmpty {
                Out.emit(vs) { "no external volumes" }
            } else {
                Out.table(["NAME", "EJECTABLE"], rows: vs.map { [$0.name, $0.ejectable ? "yes" : "no"] })
            }
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
            let all = Eject.vols()
            let vs = all.filter(\.ejectable).map(\.name)
            let skipped = all.filter { !$0.ejectable }.map(\.name)
            if vs.isEmpty { Out.emit([String]()) { "no ejectable volumes" }; return }
            Out.confirm("Eject \(vs.count) volumes: \(vs.joined(separator: ", "))?", yes: yes)
            var ok: [String] = [], failed: [String] = []
            for v in vs {
                if Shell.run("/usr/sbin/diskutil", ["eject", "/Volumes/\(v)"]).status == 0 { ok.append(v) } else { failed.append(v) }
            }
            Out.emit(["ejected": ok, "failed": failed, "skipped": skipped] as [String: [String]]) {
                "ejected \(ok.count)" + (failed.isEmpty ? "" : " — failed: \(failed.joined(separator: ", "))")
            }
        }
    }
}
