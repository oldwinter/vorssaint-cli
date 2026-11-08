// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation

struct Brew: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Homebrew management without the terminal ritual",
        discussion: "Structured wrapper over `brew`. Requires Homebrew (checked by `vorssaint doctor`).",
        subcommands: [List.self, Search.self, Info.self, Install.self, Uninstall.self, Outdated.self, Upgrade.self],
        defaultSubcommand: List.self
    )

    static func brew() -> String? { Shell.which("brew") }
    static func require() -> String {
        guard let b = brew() else { Out.fail("missing_dep", "brew not found — install from https://brew.sh", exit: .notFound) }
        return b
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List installed formulae and casks")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint brew list")
            let b = Brew.require()
            let f = Shell.run(b, ["list", "--formula"]).stdout.split(separator: "\n").map(String.init)
            let c = Shell.run(b, ["list", "--cask"]).stdout.split(separator: "\n").map(String.init)
            struct R: Encodable { var formulae: [String], casks: [String] }
            if Out.json { Out.emit(R(formulae: f, casks: c)) { "" } }
            else {
                if !f.isEmpty { print(ANSI.dim("formulae (\(f.count))")); print("  " + f.joined(separator: "  ")) }
                if !c.isEmpty { print(ANSI.dim("casks (\(c.count))")); print("  " + c.joined(separator: "  ")) }
            }
        }
    }

    struct Search: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Search formulae and casks")
        @OptionGroup var g: GlobalOptions
        @Argument var query: String
        func run() throws {
            wireOutput(g, command: "vorssaint brew search")
            let r = Shell.run(Brew.require(), ["search", query])
            let lines = r.stdout.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if Out.json { Out.emit(lines) { "" } }
            else { print(r.stdout, terminator: r.stdout.hasSuffix("\n") ? "" : "\n") }
        }
    }

    struct Info: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show package info")
        @OptionGroup var g: GlobalOptions
        @Argument var package: String
        func run() throws {
            wireOutput(g, command: "vorssaint brew info")
            let r = Shell.run(Brew.require(), ["info", package])
            guard r.status == 0 else { Out.fail("brew_failed", r.stderr, exit: .notFound) }
            if Out.json {
                // passthrough brew's own JSON
                let jr = Shell.run(Brew.require(), ["info", "--json=v2", package])
                FileHandle.standardOutput.write(Data(jr.stdout.utf8))
            } else { print(r.stdout, terminator: r.stdout.hasSuffix("\n") ? "" : "\n") }
        }
    }

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Install a formula or cask")
        @OptionGroup var g: GlobalOptions
        @Argument var package: String
        @Flag(name: .long, help: "Treat as cask") var cask = false
        @Flag(name: .long) var yes = false
        func run() throws {
            wireOutput(g, command: "vorssaint brew install")
            Out.confirm("Install \(cask ? "cask" : "formula") \(package)?", yes: yes)
            var args = ["install", package]
            if cask { args.insert("--cask", at: 1) }
            // install runs long: stream output to stderr so stdout stays clean for --json
            let status = Shell.passthrough(Brew.require(), args)
            guard status == 0 else { Out.fail("install_failed", "brew install exited \(status)") }
            Out.emit(["installed": package]) { "installed \(package)" }
        }
    }

    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove a formula or cask")
        @OptionGroup var g: GlobalOptions
        @Argument var package: String
        @Flag(name: .long) var cask = false
        @Flag(name: .long) var yes = false
        func run() throws {
            wireOutput(g, command: "vorssaint brew uninstall")
            Out.confirm("Uninstall \(package)?", yes: yes)
            var args = ["uninstall", package]
            if cask { args.insert("--cask", at: 1) }
            let status = Shell.passthrough(Brew.require(), args)
            guard status == 0 else { Out.fail("uninstall_failed", "brew uninstall exited \(status)") }
            Out.emit(["uninstalled": package]) { "uninstalled \(package)" }
        }
    }

    struct Outdated: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List packages with updates")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint brew outdated")
            let b = Brew.require()
            let r = Shell.run(b, ["outdated", "--json=v2"])
            if Out.json {
                FileHandle.standardOutput.write(Data(r.stdout.utf8))
                return
            }
            // human: parse brew's JSON into a flat table
            struct Pkg: Decodable { var name: String; var installed_versions: [String]; var current_version: String }
            struct Root: Decodable { var formulae: [Pkg]; var casks: [Pkg] }
            var rows: [[String]] = []
            if let d = r.stdout.data(using: .utf8), let root = try? JSONDecoder().decode(Root.self, from: d) {
                for p in root.formulae { rows.append([p.name, p.installed_versions.last ?? "?", p.current_version, "formula"]) }
                for p in root.casks { rows.append([p.name, p.installed_versions.last ?? "?", p.current_version, "cask"]) }
            }
            if rows.isEmpty { print("everything up to date") }
            else { Out.table(["PACKAGE", "INSTALLED", "LATEST", "KIND"], rows: rows) }
        }
    }

    struct Upgrade: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Upgrade outdated packages")
        @OptionGroup var g: GlobalOptions
        @Argument(help: "Specific package; omit for all") var package: String?
        @Flag(name: .long) var yes = false
        func run() throws {
            wireOutput(g, command: "vorssaint brew upgrade")
            Out.confirm("Run brew upgrade \(package ?? "(all)")?", yes: yes)
            var args = ["upgrade"]
            if let package { args.append(package) }
            let status = Shell.passthrough(Brew.require(), args)
            guard status == 0 else { Out.fail("upgrade_failed", "brew upgrade exited \(status)") }
            Out.emit(["upgraded": package ?? "all"]) { "upgrade finished" }
        }
    }
}
