// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ArgumentParser
import Foundation

struct Snip: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Text snippets: expand triggers into text",
        discussion: """
        Variables in expansion text: {{date}} {{time}} {{datetime}} {{clipboard}} {{uuid}} {{user}}
          vorssaint snip add sig "Best, $USER"          (or pipe text to stdin)
          vorssaint snip expand sig --copy              render → clipboard
        """
    , subcommands: [List.self, Add.self, Expand.self, RemoveCmd.self])

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List snippets")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint snip list")
            let snips = Store.load().snippets
            if Out.json { Out.emit(snips) { "" } }
            else {
                if snips.isEmpty { print("no snippets — `vorssaint snip add <trigger> <text>`") }
                else { Out.table(["TRIGGER", "EXPANSION"], rows: snips.map { [$0.trigger, String($0.expansion.prefix(60))] }) }
            }
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add a snippet")
        @OptionGroup var g: GlobalOptions
        @Argument var trigger: String
        @Argument(help: "Expansion text; omit to read stdin") var text: String?
        func run() throws {
            wireOutput(g, command: "vorssaint snip add")
            let expansion: String
            if let text { expansion = text }
            else {
                expansion = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .newlines)
            }
            guard !expansion.isEmpty else { throw ValidationError("empty expansion") }
            var c = Store.load()
            c.snippets.removeAll { $0.trigger == trigger }
            c.snippets.append(Snippet(trigger: trigger, expansion: expansion,
                                      created: ISO8601DateFormatter().string(from: Date())))
            do { try Store.save(c) } catch { Out.fail("save_failed", error.localizedDescription) }
            Out.emit(["trigger": trigger]) { "snippet '\(trigger)' saved" }
        }
    }

    struct Expand: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Render a snippet to stdout (or --copy)")
        @OptionGroup var g: GlobalOptions
        @Argument var trigger: String
        @Flag(name: .long) var copy = false
        func run() throws {
            wireOutput(g, command: "vorssaint snip expand")
            guard let s = Store.load().snippets.first(where: { $0.trigger == trigger }) else {
                Out.fail("not_found", "no snippet '\(trigger)'", exit: .notFound)
            }
            let rendered = Store.expand(s.expansion)
            if copy {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(rendered, forType: .string)
            }
            struct R: Encodable { var trigger: String, rendered: String, copied: Bool }
            Out.emit(R(trigger: trigger, rendered: rendered, copied: copy)) {
                copy ? "copied \(rendered.utf8.count) bytes" : rendered
            }
        }
    }

    struct RemoveCmd: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "remove", abstract: "Remove a snippet")
        @OptionGroup var g: GlobalOptions
        @Argument var trigger: String
        func run() throws {
            wireOutput(g, command: "vorssaint snip remove")
            var c = Store.load()
            let n = c.snippets.count
            c.snippets.removeAll { $0.trigger == trigger }
            guard c.snippets.count < n else { Out.fail("not_found", "no snippet '\(trigger)'", exit: .notFound) }
            try Store.save(c)
            Out.emit(["removed": trigger]) { "removed '\(trigger)'" }
        }
    }
}
