// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation
import IOKit.pwr_mgt

struct Awake: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Keep the Mac awake (caffeinate-style)",
        discussion: """
        Blocks sleep until the duration ends, a watched pid exits, or Ctrl-C.
        Examples:
          vorssaint awake --for 3600        # one hour
          vorssaint awake --while 4242      # until pid 4242 exits
          vorssaint awake --display         # also keep the display on
        """
    )
    @OptionGroup var g: GlobalOptions
    @Option(name: .customLong("for"), help: "Keep awake this many seconds") var duration: Double?
    @Option(name: .customLong("while"), help: "Keep awake while this pid is alive") var whilePid: Int32?
    @Flag(name: .long, help: "Also prevent display sleep") var display = false

    func run() throws {
        wireOutput(g, command: "vorssaint awake")
        var assertion: IOPMAssertionID = 0
        let type = display ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        let kr = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                             "vorssaint awake" as CFString, &assertion)
        guard kr == kIOReturnSuccess else { Out.fail("assertion_failed", "IOPMAssertion failed (\(kr))") }
        defer { IOPMAssertionRelease(assertion) }

        let mode: String
        if let whilePid { mode = "until pid \(whilePid) exits" }
        else if let duration { mode = "for \(fmtDuration(duration))" }
        else { mode = "until interrupted (Ctrl-C)" }
        FileHandle.standardError.write(Data("awake \(mode) — \(display ? "display+system" : "system") sleep prevented\n".utf8))

        var interrupted = false
        signal(SIGINT, SIG_IGN)
        let sigSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigSrc.setEventHandler { interrupted = true }
        sigSrc.resume()

        let deadline = duration.map { Date().addingTimeInterval($0) }
        var reason = "interrupted"
        while !interrupted {
            if let d = deadline, Date() >= d { reason = "duration_elapsed"; break }
            if let p = whilePid, kill(p, 0) != 0 { reason = "pid_exited"; break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        struct Done: Encodable { var reason: String }
        Out.emit(Done(reason: reason)) { "awake finished (\(reason.replacingOccurrences(of: "_", with: " ")))" }
    }
}
