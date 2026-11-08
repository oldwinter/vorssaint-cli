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
        @Flag(name: .long, help: "Write the clipboard image as raw PNG (stdout or --out)") var image = false
        @Option(name: .long, help: "Write image data to this file instead of stdout") var out: String?

        static func pngData(_ pb: NSPasteboard) -> Data? {
            if let png = pb.data(forType: .png) { return png }
            guard let tiff = pb.data(forType: .tiff),
                  let rep = NSBitmapImageRep(data: tiff) else { return nil }
            return rep.representation(using: .png, properties: [:])
        }

        func run() throws {
            wireOutput(g, command: "vorssaint clip get")
            let pb = NSPasteboard.general
            if types {
                let t = (pb.types ?? []).map(\.rawValue)
                Out.emit(t) { t.joined(separator: "\n") }
                return
            }
            if image {
                guard let png = Self.pngData(pb) else {
                    Out.fail("empty", "clipboard holds no PNG/TIFF image", exit: .notFound)
                }
                if let out {
                    let path = (out as NSString).expandingTildeInPath
                    do { try png.write(to: URL(fileURLWithPath: path)) }
                    catch { Out.fail("write_failed", "cannot write \(path): \(error.localizedDescription)") }
                    struct R: Encodable { var path: String, bytes: Int, format: String }
                    Out.emit(R(path: path, bytes: png.count, format: "png")) {
                        "saved \(path) (\(fmtBytes(UInt64(png.count))))"
                    }
                    return
                }
                if Out.json {
                    struct R: Encodable { var format: String, bytes: Int, base64: String }
                    Out.emit(R(format: "png", bytes: png.count, base64: png.base64EncodedString())) { "" }
                    return
                }
                if stdoutIsTTY {
                    Out.fail("usage",
                             "refusing to write binary to a terminal — use `clip get --image --out file.png` or redirect stdout",
                             exit: .usage)
                }
                FileHandle.standardOutput.write(png)
                return
            }
            if let img = pb.data(forType: .tiff), let s = NSBitmapImageRep(data: img) {
                struct Img: Encodable { var type: String, width: Int, height: Int, bytes: Int }
                Out.emit(Img(type: "image", width: s.pixelsWide, height: s.pixelsHigh, bytes: img.count)) {
                    "(image \(s.pixelsWide)×\(s.pixelsHigh), \(fmtBytes(UInt64(img.count))) — `clip get --image` writes PNG)"
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
        static let configuration = CommandConfiguration(abstract: "Copy text or an image to the clipboard")
        @OptionGroup var g: GlobalOptions
        @Argument(help: "Text; omit to read stdin (ignored with --image)") var text: String?
        @Flag(name: .long, help: "Also strip formatting when writing (always plain)") var plainText = false
        @Option(name: .long, help: "Copy an image file (png/jpg/tiff/heic) instead of text") var image: String?

        func run() throws {
            wireOutput(g, command: "vorssaint clip set")
            if let image {
                guard text == nil else {
                    Out.fail("usage", "pass either text or --image, not both", exit: .usage)
                }
                try copyImage(image)
                return
            }
            let input: String
            if let text { input = text }
            else {
                input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
                if input.isEmpty { throw ValidationError("nothing to copy — pass text, pipe stdin, or use --image") }
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(input, forType: .string)
            struct R: Encodable { var copied: Int }
            Out.emit(R(copied: input.utf8.count)) { "copied \(input.utf8.count) bytes" }
        }

        private func copyImage(_ path: String) throws {
            let full = (path as NSString).expandingTildeInPath
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: full)) else {
                Out.fail("not_found", "cannot read image \(full)", exit: .notFound)
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            var wrote = false
            let ext = (full as NSString).pathExtension.lowercased()
            switch ext {
            case "png":
                wrote = pb.setData(data, forType: .png) || wrote
                if let rep = NSBitmapImageRep(data: data),
                   let tiff = rep.representation(using: .tiff, properties: [:]) {
                    wrote = pb.setData(tiff, forType: .tiff) || wrote
                }
            case "tif", "tiff":
                wrote = pb.setData(data, forType: .tiff) || wrote
                if let rep = NSBitmapImageRep(data: data),
                   let png = rep.representation(using: .png, properties: [:]) {
                    wrote = pb.setData(png, forType: .png) || wrote
                }
            default:
                guard let img = NSImage(data: data) else {
                    Out.fail("unsupported", "cannot decode \(full) as an image")
                }
                if let tiff = img.tiffRepresentation {
                    wrote = pb.setData(tiff, forType: .tiff) || wrote
                    if let rep = NSBitmapImageRep(data: tiff),
                       let png = rep.representation(using: .png, properties: [:]) {
                        wrote = pb.setData(png, forType: .png) || wrote
                    }
                }
            }
            guard wrote else { Out.fail("set_failed", "could not place \(full) on the clipboard") }
            struct R: Encodable { var copiedBytes: Int, type: String, name: String }
            Out.emit(R(copiedBytes: data.count, type: "image", name: (full as NSString).lastPathComponent)) {
                "copied image \((full as NSString).lastPathComponent) (\(fmtBytes(UInt64(data.count))))"
            }
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
