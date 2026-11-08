// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ArgumentParser
import Foundation

struct Clip: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Read, write and clear the clipboard",
        subcommands: [Get.self, Set.self, Clear.self],
        defaultSubcommand: Get.self,
        aliases: ["clipboard", "cb"]
    )

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print clipboard contents")
        @OptionGroup var g: GlobalOptions
        @Flag(name: .long, help: "Force plain-text representation") var plainText = false
        @Flag(name: .long, help: "List available pasteboard types only") var types = false
        func run() throws {
            wireOutput(g, command: "vorssaint clip get")
            let pb = NSPasteboard.general
            if types {
                let t = (pb.types ?? []).map(\.rawValue)
                Out.emit(t) { t.joined(separator: "\n") }
                return
            }
            if let img = pb.data(forType: .tiff), let s = NSBitmapImageRep(data: img) {
                struct Img: Encodable { var type: String, width: Int, height: Int, bytes: Int }
                Out.emit(Img(type: "image", width: s.pixelsWide, height: s.pixelsHigh, bytes: img.count)) {
                    "(image \(s.pixelsWide)×\(s.pixelsHigh), \(fmtBytes(UInt64(img.count))) — use `clip get --types`, or `shot`/`ocr` for image ops)"
                }
                return
            }
            guard let s = pb.string(forType: .string) else {
                Out.fail("empty", "clipboard is empty or holds an unsupported type", exit: .notFound)
            }
            struct C: Encodable { var text: String, changeCount: Int }
            Out.emit(C(text: s, changeCount: pb.changeCount)) { s }
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Copy text (argument or stdin) to the clipboard")
        @OptionGroup var g: GlobalOptions
        @Argument(help: "Text; omit to read stdin") var text: String?
        @Flag(name: .long, help: "Also strip formatting when writing (always plain)") var plainText = false
        func run() throws {
            wireOutput(g, command: "vorssaint clip set")
            let input: String
            if let text { input = text }
            else {
                input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
                if input.isEmpty { throw ValidationError("nothing to copy — pass text or pipe stdin") }
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(input, forType: .string)
            struct R: Encodable { var copied: Int }
            Out.emit(R(copied: input.utf8.count)) { "copied \(input.utf8.count) bytes" }
        }
    }

    struct Clear: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Clear the clipboard")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint clip clear")
            NSPasteboard.general.clearContents()
            Out.emit(["cleared": true]) { "clipboard cleared" }
        }
    }
}
