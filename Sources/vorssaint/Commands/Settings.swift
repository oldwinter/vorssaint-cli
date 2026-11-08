// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation

struct Settings: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Config file management",
        subcommands: [Path.self, Export.self, Import.self],
        defaultSubcommand: Path.self
    )

    struct Path: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print config file location")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint settings path")
            Out.emit(["path": Store.configPath.path]) { Store.configPath.path }
        }
    }

    struct Export: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Export config to a file")
        @OptionGroup var g: GlobalOptions
        @Argument var dest: String
        func run() throws {
            wireOutput(g, command: "vorssaint settings export")
            guard FileManager.default.fileExists(atPath: Store.configPath.path) else {
                Out.fail("not_found", "no config yet — nothing to export", exit: .notFound)
            }
            do { try FileManager.default.copyItem(at: Store.configPath, to: URL(fileURLWithPath: dest)) }
            catch { Out.fail("export_failed", error.localizedDescription) }
            Out.emit(["exported": dest]) { "exported → \(dest)" }
        }
    }

    struct Import: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Import a config file")
        @OptionGroup var g: GlobalOptions
        @Argument var src: String
        @Flag(name: .long) var yes = false
        func run() throws {
            wireOutput(g, command: "vorssaint settings import")
            guard let d = try? Data(contentsOf: URL(fileURLWithPath: src)),
                  (try? JSONDecoder().decode(Config.self, from: d)) != nil else {
                Out.fail("invalid", "\(src) is not a valid vorssaint config", exit: .runtime)
            }
            Out.confirm("Overwrite \(Store.configPath.path)?", yes: yes)
            do {
                try FileManager.default.createDirectory(at: Store.dir, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: Store.configPath.path) {
                    try FileManager.default.removeItem(at: Store.configPath)
                }
                try FileManager.default.copyItem(at: URL(fileURLWithPath: src), to: Store.configPath)
            } catch { Out.fail("import_failed", error.localizedDescription) }
            Out.emit(["imported": src]) { "imported ← \(src)" }
        }
    }
}
