// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

struct ShellResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum Shell {
    /// Run a binary, capture output. Never throws; check `status`.
    @discardableResult
    static func run(_ path: String, _ args: [String], env: [String: String]? = nil) -> ShellResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        if let env { p.environment = env }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch {
            return ShellResult(status: -1, stdout: "", stderr: "failed to launch \(path): \(error.localizedDescription)")
        }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return ShellResult(
            status: p.terminationStatus,
            stdout: String(decoding: o, as: UTF8.self),
            stderr: String(decoding: e, as: UTF8.self)
        )
    }

    static func which(_ name: String) -> String? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/usr/sbin", "/bin", "/sbin"] {
            let p = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        let r = run("/usr/bin/which", [name])
        let path = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return (r.status == 0 && !path.isEmpty) ? path : nil
    }

    /// Run an interactive command inheriting stdio (for TUI-ish tools we intentionally passthrough).
    static func passthrough(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
