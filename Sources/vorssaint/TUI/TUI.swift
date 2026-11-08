// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation

// Tiny ANSI TUI loop: alternate screen, hide cursor, raw input, redraw each tick.
// `q`, Esc or Ctrl-C exits.

/// Set by the SIGWINCH handler; polled by the render loop to force a repaint.
private nonisolated(unsafe) var _tuiResized = false
private func _tuiOnWinch(_: Int32) { _tuiResized = true }

enum TUI {
    nonisolated(unsafe) private static var original = termios()

    enum Key: Equatable {
        case up, down, left, right, enter, quit, char(Character)
    }

    static func run(refresh: TimeInterval = 1.0, _ render: @escaping () -> String) {
        runInteractive(refresh: refresh, render: render) { key in
            key == .quit ? false : true
        }
    }

    /// Interactive loop: renders, dispatches keys. onKey returns false to exit.
    /// Returns the last key received when exit was caused by .enter (for switchers).
    @discardableResult
    static func runInteractive(refresh: TimeInterval = 1.0,
                               render: @escaping () -> String,
                               onKey: @escaping (Key) -> Bool) -> Key? {
        guard stdoutIsTTY else { print(render()); return nil }

        var raw = termios()
        tcgetattr(STDIN_FILENO, &original)
        raw = original
        raw.c_lflag &= ~UInt(ICANON | ECHO)
        raw.c_cc.16 = 0 // VMIN
        raw.c_cc.17 = 1 // VTIME (tenths of a second)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)

        print("\u{1B}[?1049h\u{1B}[?25l", terminator: "")
        fflush(stdout)

        signal(SIGINT, SIG_IGN)
        // SIGWINCH without SA_RESTART → select() returns EINTR → repaint next loop.
        var sa = sigaction()
        sa.__sigaction_u.__sa_handler = _tuiOnWinch
        sigemptyset(&sa.sa_mask)
        sigaction(SIGWINCH, &sa, nil)
        var last: Key?
        defer {
            print("\u{1B}[?25h\u{1B}[?1049l", terminator: "")
            fflush(stdout)
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
            signal(SIGWINCH, SIG_DFL)
        }

        var done = false
        while !done {
            _tuiResized = false
            let (cols, rows) = size()
            print("\u{1B}[H\u{1B}[2J" + fit(render(), cols: cols, rows: rows), terminator: "")
            fflush(stdout)
            var fds = fd_set()
            fdZero(&fds); fdSet(STDIN_FILENO, &fds)
            var tv = timeval(tv_sec: Int(refresh), tv_usec: Int32((refresh - TimeInterval(Int(refresh))) * 1_000_000))
            if select(STDIN_FILENO + 1, &fds, nil, nil, &tv) <= 0 || _tuiResized { continue }
            guard let key = readKey() else { continue }
            last = key
            if !onKey(key) { done = true }
        }
        return last
    }

    private static func readByte(timeoutMs: Int) -> UInt8? {
        var fds = fd_set()
        fdZero(&fds); fdSet(STDIN_FILENO, &fds)
        var tv = timeval(tv_sec: 0, tv_usec: Int32(timeoutMs * 1000))
        guard select(STDIN_FILENO + 1, &fds, nil, nil, &tv) > 0 else { return nil }
        var c = UInt8(0)
        return read(STDIN_FILENO, &c, 1) == 1 ? c : nil
    }

    private static func readKey() -> Key? {
        guard let c = readByte(timeoutMs: 50) else { return nil }
        switch c {
        case 3, UInt8(ascii: "q"): return .quit
        case 13, 10: return .enter
        case 27:
            guard readByte(timeoutMs: 10) == UInt8(ascii: "["), let arrow = readByte(timeoutMs: 10) else { return .quit }
            switch arrow {
            case UInt8(ascii: "A"): return .up
            case UInt8(ascii: "B"): return .down
            case UInt8(ascii: "C"): return .right
            case UInt8(ascii: "D"): return .left
            default: return nil
            }
        default:
            // Keys arrive byte-wise: accumulate multi-byte UTF-8 (CJK app
            // names, emoji) and emit .char only for a complete scalar.
            // ASCII and control bytes (incl. 0x7F backspace) pass through.
            let width: Int
            switch c {
            case 0x00...0x7F: width = 1
            case 0xC2...0xDF: width = 2
            case 0xE0...0xEF: width = 3
            case 0xF0...0xF4: width = 4
            default: return nil // stray continuation / invalid lead byte
            }
            var bytes = [c]
            while bytes.count < width {
                guard let next = readByte(timeoutMs: 10), next & 0xC0 == 0x80 else { return nil }
                bytes.append(next)
            }
            let text = String(decoding: bytes, as: UTF8.self)
            guard text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first else { return nil }
            return .char(Character(scalar))
        }
    }

    private static func fdZero(_ set: inout fd_set) { set.fds_bits = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0) }
    private static func fdSet(_ fd: Int32, _ set: inout fd_set) {
        let idx = Int(fd) / 32, bit = Int(fd) % 32
        switch idx {
        case 0: set.fds_bits.0 |= 1 << bit
        case 1: set.fds_bits.1 |= 1 << bit
        case 2: set.fds_bits.2 |= 1 << bit
        case 3: set.fds_bits.3 |= 1 << bit
        case 4: set.fds_bits.4 |= 1 << bit
        case 5: set.fds_bits.5 |= 1 << bit
        case 6: set.fds_bits.6 |= 1 << bit
        case 7: set.fds_bits.7 |= 1 << bit
        default: break
        }
    }

    /// Live terminal size (cols, rows) via TIOCGWINSZ; falls back to 80×24.
    static func size() -> (cols: Int, rows: Int) {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0, ws.ws_col > 0, ws.ws_row > 0 {
            return (Int(ws.ws_col), Int(ws.ws_row))
        }
        return (80, 24)
    }

    /// Pads a line to `cols` visible columns (ANSI-aware).
    static func pad(_ s: String, cols: Int) -> String {
        let w = visibleWidth(s)
        return w >= cols ? s : s + String(repeating: " ", count: cols - w)
    }

    /// Visible column count, ignoring ANSI CSI escape sequences.
    static func visibleWidth(_ s: String) -> Int {
        var n = 0, i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\u{1B}", let end = csiEnd(in: s, from: i) { i = end; continue }
            n += 1
            i = s.index(after: i)
        }
        return n
    }

    /// Clips a frame to the terminal: lines truncated to `cols` visible
    /// columns, no more than `rows` lines emitted.
    private static func fit(_ frame: String, cols: Int, rows: Int) -> String {
        frame.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(rows)
            .map { truncate(String($0), cols: cols) }
            .joined(separator: "\n")
    }

    /// Truncates a line to `cols` visible columns, keeping ANSI sequences;
    /// a cut inside styled text gets a reset so attributes can't bleed.
    private static func truncate(_ s: String, cols: Int) -> String {
        var out = "", n = 0, i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\u{1B}", let end = csiEnd(in: s, from: i) {
                out.append(contentsOf: s[i..<end]); i = end; continue
            }
            if n >= cols { break }
            out.append(s[i]); n += 1; i = s.index(after: i)
        }
        if i < s.endIndex, s.contains("\u{1B}") { out += "\u{1B}[0m" }
        return out
    }

    /// Index just past an ANSI CSI sequence starting at `esc` (ESC '[' … final byte 0x40–0x7E).
    private static func csiEnd(in s: String, from esc: String.Index) -> String.Index? {
        var i = s.index(after: esc)
        guard i < s.endIndex, s[i] == "[" else { return nil }
        i = s.index(after: i)
        while i < s.endIndex {
            if ("\u{40}"..."\u{7E}").contains(s[i]) { return s.index(after: i) }
            i = s.index(after: i)
        }
        return s.endIndex
    }

    static func bar(_ pct: Double, width: Int = 24) -> String {
        let filled = Int((pct / 100 * Double(width)).rounded())
        let safe = max(0, min(width, filled))
        let color = pct > 85 ? ANSI.red : (pct > 60 ? ANSI.yellow : ANSI.green)
        return color(String(repeating: "█", count: safe)) + ANSI.dim(String(repeating: "░", count: width - safe))
    }
}

struct Top: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Full-screen live dashboard (q to quit)",
        discussion: "TUI view of CPU, memory, disk, network throughput, battery and fans."
    )
    @Option(help: "Refresh interval seconds") var interval: Double = 1.0

    func run() throws {
        var prevCPU = CPUTicks.sample()
        var prevNet = NetCounters.sample()
        var cpuBusy = 0.0, cpuUser = 0.0, cpuSys = 0.0
        var rates: [Monitor.IfaceRate] = []

        TUI.run(refresh: interval) {
            let t = CPUTicks.sample()
            let u = CPUTicks.usage(between: prevCPU, and: t)
            cpuBusy = u.used; cpuUser = u.user; cpuSys = u.sys
            prevCPU = t
            let n = NetCounters.sample()
            rates = Monitor.NetData.rates(prevNet, n, dt: interval)
            prevNet = n

            let m = Memory.stats()
            let d = Disk.stats()
            let b = Battery.stats()
            let h = Sys.hostInfo()
            var o = ANSI.bold("  vorssaint top") + ANSI.dim("  —  q to quit  ·  \(h.chip) · up \(fmtDuration(Sys.uptimeSeconds()))") + "\n\n"
            o += String(format: "  CPU  %@ %5.1f%%   user %.1f  sys %.1f  load %.2f\n", TUI.bar(cpuBusy), cpuBusy, cpuUser, cpuSys, Sys.loadAvg()[0])
            o += String(format: "  MEM  %@ %5.1f%%   %@ / %@\n", TUI.bar(m.usedPercent), m.usedPercent, fmtBytes(m.usedBytes), fmtBytes(m.totalBytes))
            if let d {
                o += String(format: "  DISK %@ %5.1f%%   %@ free of %@\n", TUI.bar(d.usedPercent), d.usedPercent, fmtBytes(d.freeBytes), fmtBytes(d.totalBytes))
            }
            o += "\n"
            for i in rates where i.rxPerSec + i.txPerSec > 1 || i.name == "en0" {
                o += String(format: "  %-6@ ↓ %10@/s   ↑ %10@/s\n", i.name,
                            fmtBytes(UInt64(max(0, i.rxPerSec))), fmtBytes(UInt64(max(0, i.txPerSec))))
            }
            o += "\n"
            if b.present {
                o += String(format: "  BAT  %@ %d%%  %@%@\n", TUI.bar(Double(b.percent), width: 12), b.percent,
                            b.charging ? "charging" : "discharging",
                            b.temperatureC.map { String(format: "  %.0f°C", $0) } ?? "")
            }
            for f in SMC.fans() {
                o += String(format: "  FAN%d %5.0f rpm\n", f.index, f.rpm)
            }
            return o
        }
    }
}
