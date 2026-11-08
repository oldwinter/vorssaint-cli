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
        // Read stderr on a side thread: sequential readDataToEndOfFile deadlocks
        // when the child fills the 64KB stderr buffer while still writing stdout.
        nonisolated(unsafe) var errData = Data()
        let t = Thread { errData = err.fileHandleForReading.readDataToEndOfFile() }
        t.start()
        let o = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        t.cancel()
        var spins = 0
        while t.isExecuting && spins < 200 { Thread.sleep(forTimeInterval: 0.01); spins += 1 }
        let e = errData
        return ShellResult(
            status: p.terminationStatus,
            stdout: String(decoding: o, as: UTF8.self),
            stderr: String(decoding: e, as: UTF8.self)
        )
    }

    static func which(_ name: String) -> String? {
        // Honour the caller's PATH first (user-installed tools beat system ones),
        // then fall back to common locations for non-login environments.
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in pathDirs + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/usr/sbin", "/bin", "/sbin"] {
            let p = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
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
