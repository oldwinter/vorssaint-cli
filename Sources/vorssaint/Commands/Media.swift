// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation

struct Media: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Local media tools (images via sips, video via ffmpeg)",
        subcommands: [Info.self, Convert.self, Gif.self, Compress.self],
        defaultSubcommand: Info.self
    )

    static func ffmpeg() -> String {
        guard let f = Shell.which("ffmpeg") else {
            Out.fail("missing_dep", "ffmpeg not found — `brew install ffmpeg`", exit: .notFound)
        }
        return f
    }

    struct Info: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "File metadata (images, audio, video)")
        @OptionGroup var g: GlobalOptions
        @Argument var file: String
        func run() throws {
            wireOutput(g, command: "vorssaint media info")
            let path = (file as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else { Out.fail("not_found", path, exit: .notFound) }
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            struct R: Encodable { var path: String, kind: String, summary: String }
            if ["png","jpg","jpeg","heic","gif","webp","tiff","bmp"].contains(ext) {
                let r = Shell.run("/usr/bin/sips", ["-g", "pixelWidth", "-g", "pixelHeight", "-g", "hasAlpha", path])
                let summary = r.stdout.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.contains(":") }.joined(separator: ", ")
                Out.emit(R(path: path, kind: "image", summary: summary)) { summary }
            } else if ["mp4","mov","mkv","webm","avi","m4v","mp3","m4a","wav","flac","aac"].contains(ext) {
                let f = Media.ffmpeg().replacingOccurrences(of: "ffmpeg", with: "ffprobe")
                let r = Shell.run(f, ["-v","quiet","-print_format","json","-show_format","-show_streams", path])
                if Out.json { FileHandle.standardOutput.write(Data(r.stdout.utf8)); return }
                let s = Shell.run(f, ["-v","error","-show_entries","format=duration,size,bit_rate:stream=codec_name,width,height","-of","default=noprint_wrappers=1", path])
                Out.emit(R(path: path, kind: "av", summary: s.stdout.trimmingCharacters(in: .whitespacesAndNewlines))) {
                    s.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else {
                let a = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
                let size = (a[.size] as? Int64) ?? 0
                Out.emit(R(path: path, kind: ext.isEmpty ? "file" : ext, summary: fmtBytes(UInt64(size)))) { "\(ext) — \(fmtBytes(UInt64(size)))" }
            }
        }
    }

    struct Convert: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Convert media format (images via sips, other via ffmpeg)")
        @OptionGroup var g: GlobalOptions
        @Argument var input: String
        @Argument var output: String
        @Option(help: "Image quality 1–100 (sips)") var quality: Int?
        func run() throws {
            wireOutput(g, command: "vorssaint media convert")
            let inp = (input as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: inp) else { Out.fail("not_found", inp, exit: .notFound) }
            let outExt = URL(fileURLWithPath: output).pathExtension.lowercased()
            let imgExts = ["png","jpg","jpeg","heic","tiff","bmp"]
            if imgExts.contains(outExt) {
                var args = ["-s", "format", outExt == "jpg" ? "jpeg" : outExt]
                if let quality { args += ["-s", "formatOptions", String(quality)] }
                args += [inp, "--out", output]
                let r = Shell.run("/usr/bin/sips", args)
                guard r.status == 0 else { Out.fail("convert_failed", r.stderr) }
            } else {
                let r = Shell.run(Media.ffmpeg(), ["-hide_banner","-loglevel","error","-y","-i",inp,output])
                guard r.status == 0 else { Out.fail("convert_failed", r.stderr) }
            }
            struct R: Encodable { var output: String }
            Out.emit(R(output: output)) { "→ \(output)" }
        }
    }

    struct Gif: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Make a GIF from a video (ffmpeg two-pass palette)")
        @OptionGroup var g: GlobalOptions
        @Argument var input: String
        @Argument(help: "Output .gif") var output: String
        @Option var fps: Int = 12
        @Option var width: Int = 480
        func run() throws {
            wireOutput(g, command: "vorssaint media gif")
            let f = Media.ffmpeg()
            let inp = (input as NSString).expandingTildeInPath
            let palette = NSTemporaryDirectory() + "vorssaint-pal-\(getpid()).png"
            defer { try? FileManager.default.removeItem(atPath: palette) }
            var r = Shell.run(f, ["-hide_banner","-loglevel","error","-y","-i",inp,
                                  "-vf","fps=\(fps),scale=\(width):-1:flags=lanczos,palettegen", palette])
            guard r.status == 0 else { Out.fail("gif_failed", "palette pass: \(r.stderr)") }
            r = Shell.run(f, ["-hide_banner","-loglevel","error","-y","-i",inp,"-i",palette,
                              "-lavfi","fps=\(fps),scale=\(width):-1:flags=lanczos [x]; [x][1:v] paletteuse", output])
            guard r.status == 0 else { Out.fail("gif_failed", r.stderr) }
            struct R: Encodable { var output: String, fps: Int, width: Int }
            Out.emit(R(output: output, fps: fps, width: width)) { "→ \(output)" }
        }
    }

    struct Compress: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Re-encode a video smaller (h264, --crf)")
        @OptionGroup var g: GlobalOptions
        @Argument var input: String
        @Argument(help: "Output; default <name>-small.mp4") var output: String?
        @Option(help: "CRF 18–35, higher = smaller/worse") var crf: Int = 26
        func run() throws {
            wireOutput(g, command: "vorssaint media compress")
            let inp = (input as NSString).expandingTildeInPath
            let out = output ?? ((inp as NSString).deletingPathExtension + "-small.mp4")
            let before = ((try? FileManager.default.attributesOfItem(atPath: inp)[.size] as? Int64) ?? 0)
            let r = Shell.run(Media.ffmpeg(), ["-hide_banner","-loglevel","error","-y","-i",inp,
                                             "-c:v","libx264","-crf",String(crf),"-preset","medium",
                                             "-c:a","aac","-b:a","128k", out])
            guard r.status == 0 else { Out.fail("compress_failed", r.stderr) }
            let after = ((try? FileManager.default.attributesOfItem(atPath: out)[.size] as? Int64) ?? 0)
            struct R: Encodable { var output: String, bytesBefore: Int64, bytesAfter: Int64 }
            Out.emit(R(output: out, bytesBefore: before, bytesAfter: after)) {
                "\(fmtBytes(UInt64(before))) → \(fmtBytes(UInt64(after)))  (\(out))"
            }
        }
    }
}
