// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ArgumentParser
import Foundation
import Vision

struct Shot: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Take a screenshot",
        discussion: """
        Wraps /usr/sbin/screencapture. Modes:
          vorssaint shot out.png                 full screen
          vorssaint shot --area out.png          interactive area select
          vorssaint shot --window out.png        interactive window pick
          vorssaint shot --clipboard             full screen to clipboard
        """
    )
    @OptionGroup var g: GlobalOptions
    @Flag(name: .long, help: "Interactive area selection") var area = false
    @Flag(name: .long, help: "Interactive window selection") var window = false
    @Flag(name: .long, help: "Copy to clipboard instead of a file") var clipboard = false
    @Option(help: "Delay seconds before capture") var delay: Int = 0
    @Argument(help: "Output file (png/jpg/pdf/tiff)") var output: String = ""
    func run() throws {
        wireOutput(g, command: "vorssaint shot")
        var args = ["-x"] // no shutter sound
        if area { args += ["-i"] }
        if window { args += ["-i", "-w"] }
        if clipboard { args += ["-c"] }
        if delay > 0 { args += ["-T", String(delay)] }
        if !clipboard {
            let out = output.isEmpty ? "screenshot-\(Int(Date().timeIntervalSince1970)).png" : output
            args.append(out)
            let r = Shell.run("/usr/sbin/screencapture", args)
            guard r.status == 0 else { Out.fail("capture_failed", r.stderr.isEmpty ? "screencapture failed" : r.stderr) }
            let exists = FileManager.default.fileExists(atPath: out)
            struct R: Encodable { var path: String, bytes: Int }
            let sz = (try? FileManager.default.attributesOfItem(atPath: out)[.size] as? Int) ?? 0
            guard exists else { Out.fail("cancelled", "no file written — capture cancelled or Screen Recording permission missing", exit: .permission) }
            Out.emit(R(path: out, bytes: sz)) { "saved \(out) (\(fmtBytes(UInt64(sz))))" }
        } else {
            let r = Shell.run("/usr/sbin/screencapture", args)
            guard r.status == 0 else { Out.fail("capture_failed", r.stderr.isEmpty ? "screencapture failed" : r.stderr) }
            Out.emit(["clipboard": true]) { "copied to clipboard" }
        }
    }
}

struct Ocr: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Offline text recognition (Vision) on an image or the screen",
        discussion: """
          vorssaint ocr --image shot.png       OCR a file
          vorssaint ocr --screen               capture full screen then OCR
          vorssaint ocr --clipboard            OCR the image on the clipboard
        """
    )
    @OptionGroup var g: GlobalOptions
    @Flag(name: .long) var screen = false
    @Flag(name: .long) var clipboard = false
    @Option(help: "Image file to OCR") var image: String?

    struct Line: Encodable { var text: String, confidence: Float }

    func run() throws {
        wireOutput(g, command: "vorssaint ocr")
        var cg: CGImage?
        var cleanup: String?
        defer { if let c = cleanup { try? FileManager.default.removeItem(atPath: c) } }

        if let image {
            guard let ns = NSImage(contentsOfFile: image)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                Out.fail("not_found", "cannot read image \(image)", exit: .notFound)
            }
            cg = ns
        } else if clipboard {
            guard let data = NSPasteboard.general.data(forType: .tiff),
                  let rep = NSBitmapImageRep(data: data),
                  let img = rep.cgImage else {
                Out.fail("empty", "no image on clipboard", exit: .notFound)
            }
            cg = img
        } else {
            let tmp = NSTemporaryDirectory() + "vorssaint-ocr-\(getpid()).png"
            cleanup = tmp
            let r = Shell.run("/usr/sbin/screencapture", ["-x", tmp])
            guard r.status == 0, FileManager.default.fileExists(atPath: tmp) else {
                Out.fail("capture_failed", "screenshot failed — grant Screen Recording permission", exit: .permission)
            }
            cg = NSImage(contentsOfFile: tmp)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        guard let cg else { Out.fail("no_image", "no image source — use --image/--clipboard/--screen") }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do { try handler.perform([request]) } catch {
            Out.fail("ocr_failed", "Vision failed: \(error.localizedDescription)")
        }
        let lines: [Line] = (request.results ?? []).compactMap { obs in
            obs.topCandidates(1).first.map { Line(text: $0.string, confidence: $0.confidence) }
        }
        Out.emit(lines) {
            lines.map(\.text).joined(separator: "\n")
        }
    }
}

struct ColorCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "color",
        abstract: "Screen colors and color conversion",
        subcommands: [At.self, Convert.self],
        defaultSubcommand: nil
    )

    struct RGB: Encodable { var hex: String, r: Int, g: Int, b: Int, h: Int, s: Int, l: Int }

    static func toHSL(_ r: Double, _ g: Double, _ b: Double) -> (Int, Int, Int) {
        let mx = max(r, g, b), mn = min(r, g, b)
        let l = (mx + mn) / 2
        var h = 0.0, s = 0.0
        if mx != mn {
            let d = mx - mn
            s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
            switch mx {
            case r: h = (g - b) / d + (g < b ? 6 : 0)
            case g: h = (b - r) / d + 2
            default: h = (r - g) / d + 4
            }
            h *= 60
        }
        return (Int(h.rounded()), Int((s * 100).rounded()), Int((l * 100).rounded()))
    }

    static func pack(_ r: Double, _ g: Double, _ b: Double) -> RGB {
        let ri = Int((r * 255).rounded()), gi = Int((g * 255).rounded()), bi = Int((b * 255).rounded())
        let (h, s, l) = toHSL(r, g, b)
        return RGB(hex: String(format: "#%02X%02X%02X", ri, gi, bi), r: ri, g: gi, b: bi, h: h, s: s, l: l)
    }

    struct At: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Sample the color at screen coordinates")
        @OptionGroup var g: GlobalOptions
        @Argument(help: "X coordinate (screen points, origin top-left of main display)") var x: Int
        @Argument var y: Int
        func run() throws {
            wireOutput(g, command: "vorssaint color at")
            let rect = CGRect(x: x, y: y, width: 1, height: 1)
            guard let img = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]) else {
                Out.fail("permission", "could not read screen pixels — grant Screen Recording permission", exit: .permission)
            }
            let rep = NSBitmapImageRep(cgImage: img)
            guard let c = rep.colorAt(x: 0, y: 0) else { Out.fail("read_failed", "no pixel at \(x),\(y)") }
            var r: CGFloat = 0, gg: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &gg, blue: &b, alpha: &a)
            let rgb = ColorCmd.pack(Double(r), Double(gg), Double(b))
            Out.emit(rgb) { "\(rgb.hex)  rgb(\(rgb.r),\(rgb.g),\(rgb.b))  hsl(\(rgb.h),\(rgb.s)%,\(rgb.l)%)" }
        }
    }

    struct Convert: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Convert between HEX/RGB/HSL")
        @OptionGroup var g: GlobalOptions
        @Argument(help: "#RRGGBB, rrggbb, or \"r,g,b\"") var color: String
        func run() throws {
            wireOutput(g, command: "vorssaint color convert")
            var r = 0.0, gg = 0.0, b = 0.0
            if color.contains(",") {
                let parts = color.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                guard parts.count == 3 else { throw ValidationError("expected r,g,b") }
                r = parts[0] / 255; gg = parts[1] / 255; b = parts[2] / 255
            } else {
                var hex = color.trimmingCharacters(in: .whitespaces)
                if hex.hasPrefix("#") { hex.removeFirst() }
                guard hex.count == 6, let v = UInt32(hex, radix: 16) else { throw ValidationError("expected #RRGGBB or r,g,b") }
                r = Double((v >> 16) & 0xFF) / 255; gg = Double((v >> 8) & 0xFF) / 255; b = Double(v & 0xFF) / 255
            }
            let rgb = ColorCmd.pack(r, gg, b)
            Out.emit(rgb) { "\(rgb.hex)  rgb(\(rgb.r),\(rgb.g),\(rgb.b))  hsl(\(rgb.h),\(rgb.s)%,\(rgb.l)%)" }
        }
    }
}
