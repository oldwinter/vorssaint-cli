// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation

// Shared output conventions:
//   human (TTY default)  — labeled values, light ANSI when a terminal is attached
//   --plain              — raw values, one per line / tab separated, no ANSI ever
//   --json               — {"ok":true,"command":"...","data":...} on stdout;
//                          {"ok":false,"error":{"code","message"}} on stderr
// Exit codes: 0 ok · 1 runtime · 2 usage · 3 not implemented · 4 permission · 5 not found

enum VExit: Int32, Error {
    case ok = 0
    case runtime = 1
    case usage = 2
    case notImplemented = 3
    case permission = 4
    case notFound = 5
}

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Emit a JSON envelope on stdout (conflicts with --plain)")
    var json = false

    @Flag(name: .long, help: "Plain output: no ANSI, no table formatting (conflicts with --json)")
    var plain = false
}

struct ErrorBody: Encodable {
    let code: String
    let message: String
}

struct ErrorEnvelope: Encodable {
    let ok = false
    let command: String
    let error: ErrorBody
}

struct OkEnvelope<D: Encodable>: Encodable {
    let ok = true
    let command: String
    let data: D
}

enum ANSI {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["NO_COLOR"] == nil
            && isatty(FileHandle.standardOutput.fileDescriptor) == 1
    }
    static func bold(_ s: String) -> String { enabled ? "\u{1B}[1m\(s)\u{1B}[0m" : s }
    static func dim(_ s: String) -> String { enabled ? "\u{1B}[2m\(s)\u{1B}[0m" : s }
    static func green(_ s: String) -> String { enabled ? "\u{1B}[32m\(s)\u{1B}[0m" : s }
    static func yellow(_ s: String) -> String { enabled ? "\u{1B}[33m\(s)\u{1B}[0m" : s }
    static func red(_ s: String) -> String { enabled ? "\u{1B}[31m\(s)\u{1B}[0m" : s }
    static func cyan(_ s: String) -> String { enabled ? "\u{1B}[36m\(s)\u{1B}[0m" : s }
}

var stdoutIsTTY: Bool { isatty(FileHandle.standardOutput.fileDescriptor) == 1 }
var stdinIsTTY: Bool { isatty(FileHandle.standardInput.fileDescriptor) == 1 }

enum Out {
    nonisolated(unsafe) static var currentCommand = "vorssaint"
    nonisolated(unsafe) static var json = false
    nonisolated(unsafe) static var plain = false

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    /// Emit a success. `human` is shown in TTY/plain mode, `data` in --json mode.
    static func emit<D: Encodable>(_ data: D, human: () -> String) {
        if json {
            let env = OkEnvelope(command: currentCommand, data: data)
            print(String(decoding: (try? encoder.encode(env)) ?? Data("{}".utf8), as: UTF8.self))
        } else {
            print(human())
        }
    }

    /// Emit a bare value (strings print raw in plain mode).
    static func value(_ s: String, json value: some Encodable) {
        emit(value, human: { s })
    }

    static func fail(_ code: String, _ message: String, exit: VExit = .runtime) -> Never {
        if json {
            let env = ErrorEnvelope(command: currentCommand, error: ErrorBody(code: code, message: message))
            FileHandle.standardError.write(Data((String(decoding: (try? encoder.encode(env)) ?? Data("{}".utf8), as: UTF8.self) + "\n").utf8))
        } else {
            FileHandle.standardError.write(Data(("vorssaint: \(message)\n").utf8))
        }
        Foundation.exit(exit.rawValue)
    }

    static func notImplemented(_ what: String) -> Never {
        fail("not_implemented", "\(what) is planned but not implemented yet. See `vorssaint features` for status.", exit: .notImplemented)
    }

    /// Table printer: list of rows of key/value-ish columns. Plain mode = tab separated.
    static func table(_ header: [String], rows: [[String]], humanWidthHint: Int = 0) {
        if plain {
            for r in rows { print(r.joined(separator: "\t")) }
            return
        }
        var widths = header.map(\.count)
        for r in rows {
            for (i, c) in r.enumerated() where i < widths.count {
                widths[i] = max(widths[i], c.count)
            }
        }
        func fmt(_ r: [String]) -> String {
            r.enumerated().map { i, c in c.padding(toLength: widths[i], withPad: " ", startingAt: 0) }.joined(separator: "  ")
        }
        print(ANSI.dim(fmt(header)))
        for r in rows { print(fmt(r)) }
    }

    /// Confirmation for destructive ops. Returns silently if --yes or non-required.
    static func confirm(_ prompt: String, yes: Bool) {
        if yes { return }
        if !stdinIsTTY {
            fail("confirmation_required", "\(prompt) — pass --yes to confirm (non-interactive).")
        }
        FileHandle.standardError.write(Data("\(prompt) [y/N] ".utf8))
        let answer = readLine(strippingNewline: true) ?? ""
        guard answer.lowercased() == "y" || answer.lowercased() == "yes" else {
            fail("aborted", "aborted by user", exit: .runtime)
        }
    }
}

extension ParsableCommand {
    /// Call at the top of run() for commands carrying GlobalOptions.
    func wireOutput(_ g: GlobalOptions, command name: String) {
        Out.currentCommand = name
        Out.json = g.json
        Out.plain = g.plain
        if g.json && g.plain {
            Out.fail("usage", "--json and --plain are mutually exclusive; pass exactly one output mode.", exit: .usage)
        }
    }
}
