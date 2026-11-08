// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation

struct Record: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Record the primary display to a video file",
        discussion: """
        Uses ScreenCaptureKit in-process. Recording stops after --duration, or
        on Ctrl-C when no duration is given.

          vorssaint record                          → ~/Movies/vorssaint-<time>.mov
          vorssaint record demo.mp4 --duration 10   → 10-second clip
          vorssaint record --display 2 out.mov      → capture another display

        Requires Screen Recording permission (checked by `vorssaint doctor`).
        """,
        aliases: ["rec"]
    )

    @OptionGroup var g: GlobalOptions
    @Argument(help: "Output file (.mov or .mp4); default ~/Movies/vorssaint-<time>.mov") var output: String = ""
    @Option(name: .long, help: "Stop after N seconds (default: until Ctrl-C)") var duration: Double = 0
    @Option(name: .long, help: "Display id from `vorssaint display list` (default: primary)") var display: UInt32?
    @Option(name: .long, help: "Frames per second (1–60)") var fps: Int = 30
    @Flag(name: .long, help: "Hide the mouse cursor") var noCursor = false

    struct Result: Encodable {
        var path: String, bytes: Int, seconds: Double, frames: Int
        var display: String, displayID: UInt32
    }

    func run() throws {
        wireOutput(g, command: "vorssaint record")
        guard duration >= 0 else { throw ValidationError("--duration must be 0 or more") }
        guard (1...60).contains(fps) else { throw ValidationError("--fps must be 1–60") }

        let path = output.isEmpty ? Self.defaultPath() : (output as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        if url.pathExtension.isEmpty {
            throw ValidationError("output needs a .mov or .mp4 extension")
        }
        let ext = url.pathExtension.lowercased()
        guard ext == "mov" || ext == "mp4" else {
            throw ValidationError("unsupported container .\(ext) — use .mov or .mp4")
        }
        if FileManager.default.fileExists(atPath: url.path) {
            Out.fail("exists", "\(url.path) already exists — choose another output path")
        }
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            do { try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true) }
            catch { Out.fail("mkdir_failed", "cannot create \(parent.path): \(error.localizedDescription)") }
        }

        let human = !Out.json
        do {
            let result = try ScreenRecorder.record(
                outputURL: url,
                displayID: display,
                duration: duration,
                fps: fps,
                showsCursor: !noCursor,
                progress: { msg in
                    if human {
                        FileHandle.standardError.write(Data((msg + (duration > 0 ? "" : "  (Ctrl-C to stop)") + "\n").utf8))
                    }
                })
            let r = Result(path: result.path, bytes: result.bytes, seconds: result.seconds,
                           frames: result.frames, display: result.display, displayID: result.displayID)
            Out.emit(r) {
                "saved \(r.path) (\(fmtBytes(UInt64(r.bytes)))) — "
                    + String(format: "%.1fs, %d frames from %@", r.seconds, r.frames, r.display)
            }
        } catch let e as ScreenRecorderError {
            var exit: VExit = .runtime
            if case .permission = e { exit = .permission }
            Out.fail("record_failed", e.description, exit: exit)
        }
    }

    private static func defaultPath() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HHmmss"
        let name = "vorssaint-\(df.string(from: Date())).mov"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent(name).path
    }
}
