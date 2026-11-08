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

extension String {
    /// Terminal cell width — the length that matters for column padding, not
    /// `count`: CJK/fullwidth scalars take 2 cells, combining marks and control
    /// characters take 0, and ANSI escape sequences take 0.
    var displayWidth: Int {
        var width = 0
        // ANSI parser state: 0 normal, 1 just saw ESC, 2 inside CSI (ESC [ … final)
        var esc = 0
        for scalar in unicodeScalars {
            let v = scalar.value
            switch esc {
            case 1:
                if v == 0x5B { esc = 2 }                 // '[' starts a CSI sequence
                else if v >= 0x30 && v <= 0x7E { esc = 0 } // ESC + final byte
            case 2:
                if v >= 0x40 && v <= 0x7E { esc = 0 }    // CSI final byte (e.g. 'm')
            default:
                if v == 0x1B { esc = 1 }
                else { width += scalar.cellWidth }
            }
        }
        return width
    }
}

private extension Unicode.Scalar {
    /// Rough wcwidth for a single scalar. East-Asian wide/fullwidth ranges
    /// count as 2 cells (Markus Kuhn's wcwidth range list); combining marks
    /// and control characters count as 0; everything else counts as 1.
    /// Wide `Character`s like flag emoji still resolve per-scalar.
    var cellWidth: Int {
        switch value {
        case 0x0000...0x001F, 0x007F...0x009F,
             0x0300...0x036F, 0x0483...0x0489, 0x0591...0x05BD,
             0x0610...0x061A, 0x064B...0x065F, 0x0670,
             0x1AB0...0x1AFF, 0x1DC0...0x1DFF, 0x20D0...0x20F0,
             0xFE00...0xFE0F, 0xFE20...0xFE2F,
             0x200B...0x200F, 0x202A...0x202E, 0x2060...0x2064:
            return 0
        case 0x1100...0x115F,              // Hangul Jamo
             0x231A...0x231B, 0x2329...0x232A, 0x23E9...0x23EC,
             0x23F0, 0x23F3, 0x25FD...0x25FE, 0x2614...0x2615,
             0x2648...0x2653, 0x267F, 0x2693, 0x26A1, 0x26AA...0x26AB,
             0x26BD...0x26BE, 0x26C4...0x26C5, 0x26CE, 0x26D4, 0x26EA,
             0x26F2...0x26F3, 0x26F5, 0x26FA, 0x26FD, 0x2705,
             0x270A...0x270B, 0x2728, 0x274C, 0x274E, 0x2753...0x2755,
             0x2757, 0x2795...0x2797, 0x27B0, 0x27BF, 0x2B1B...0x2B1C,
             0x2B50, 0x2B55,
             0x2E80...0xA4CF,              // CJK radicals … Yi (covers Han, Kana, Hangul Jamo, Bopomofo)
             0xAC00...0xD7A3,              // Hangul syllables
             0xF900...0xFAFF,              // CJK compat ideographs
             0xFE30...0xFE6F,              // CJK compat forms
             0xFF00...0xFF60, 0xFFE0...0xFFE6, // fullwidth forms
             0x16FE0...0x16FE4,
             0x1B000...0x1B152,
             0x1F200...0x1F2FF, 0x1F300...0x1F64F, 0x1F680...0x1F6FF,
             0x1F900...0x1F9FF, 0x1FA70...0x1FAFF, // emoji & pictographs
             0x20000...0x3FFFD:            // CJK ext B and beyond
            return 2
        default:
            return 1
        }
    }
}

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
        var widths = header.map(\.displayWidth)
        for r in rows {
            for (i, c) in r.enumerated() where i < widths.count {
                widths[i] = max(widths[i], c.displayWidth)
            }
        }
        func fmt(_ r: [String]) -> String {
            // Pad by terminal cells (String.padding counts characters, not width).
            r.enumerated().map { i, c in
                let pad = widths[i] - c.displayWidth
                return pad > 0 ? c + String(repeating: " ", count: pad) : c
            }.joined(separator: "  ")
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
