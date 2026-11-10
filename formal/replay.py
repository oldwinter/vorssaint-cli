"""Execute covered Swift method bodies with isolated dependencies and scratch mutations."""
from __future__ import annotations

import json
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import termios
import time
import re


def block(source: str, marker: str) -> str:
    """Extract a Swift declaration; mask comments and strings before balancing braces."""
    mask = re.sub(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"',
                  lambda m: " " * len(m[0]), source, flags=re.S)
    start = source.index(marker)
    opening = mask.index("{", start)
    depth = 1
    for end in range(opening + 1, len(mask)):
        depth += (mask[end] == "{") - (mask[end] == "}")
        if depth == 0:
            return source[start:end + 1]
    raise RuntimeError(f"unbalanced source: {marker}")


def body(source: str, marker: str) -> str:
    declaration = block(source, marker)
    return declaration[declaration.index("{") + 1:-1]


def change(source: str, old: str, new: str) -> str:
    if source.count(old) != 1:
        raise RuntimeError(f"mutation must have one target: {old!r}")
    return source.replace(old, new)


def compile_swift(folder: Path, source: str) -> Path:
    folder.mkdir(parents=True)
    path = folder / "main.swift"
    path.write_text(source)
    binary = folder / "replay"
    result = subprocess.run(["swiftc", "-swift-version", "5", str(path), "-o", str(binary)],
                            capture_output=True, text=True, timeout=60)
    (folder / "compile.log").write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f"Swift replay did not compile: {folder / 'compile.log'}")
    return binary


def run(binary: Path, *args: str, timeout: float = 5) -> tuple[int, str]:
    p = subprocess.run([str(binary), *args], stdin=subprocess.DEVNULL,
                       capture_output=True, text=True, timeout=timeout)
    return p.returncode, p.stdout + p.stderr


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def prelude(root: Path) -> str:
    output = (root / "Sources/vorssaint/Core/Output.swift").read_text()
    output = output.replace("import ArgumentParser\n", "")
    output = output.replace(block(output, "struct GlobalOptions:"),
                            "struct GlobalOptions { var json = false; var plain = false }")
    output = output[:output.index("extension ParsableCommand")]
    return output + r'''
func trace(_ text: String) { FileHandle.standardError.write(Data(("TRACE " + text + "\n").utf8)) }
let g = GlobalOptions()
func wireOutput(_ g: GlobalOptions, command: String) { Out.currentCommand = command }
struct ValidationError: Error { init(_ s: String) {} }
func fmtBytes(_ n: UInt64) -> String { String(n) }
func fmtDuration(_ n: Double) -> String { String(n) }
'''


def dmg_source(root: Path, source: str) -> str:
    method = body(block(source, "struct Install:"), "func run() throws")
    return prelude(root) + r'''
struct ShellResult { let status: Int32; let stderr = "injected failure" }
enum Shell {
 static func run(_ p: String, _ args: [String]) -> ShellResult {
  trace(args[0])
  return ShellResult(status: args[0] == "attach" ? 0 : (args[0] == "detach" ? 0 : (mode == "copy-fails" ? 1 : 0)))
 }
}
class FileManager {
 static let `default` = FileManager()
 func fileExists(atPath: String) -> Bool { true }
 func contentsOfDirectory(atPath: String) throws -> [String] { mode == "no-app" ? [] : ["Demo.app"] }
 func removeItem(atPath: String) throws {
  trace("remove " + atPath)
  if atPath == "/scratch/input.dmg" { throw ValidationError("injected cleanup failure") }
 }
}
let mode = CommandLine.arguments[1]
let dmg = "/scratch/input.dmg", to = "/scratch/Applications", yes = mode != "unconfirmed"
let cleanup = mode == "cleanup-fails"
func command() throws {
''' + method + "\n}\ntry command()\n"


def files_source(root: Path, source: str) -> str:
    method = body(block(source, "struct Run:"), "func run() throws")
    return prelude(root) + r'''
struct Entry: Encodable { var path: String, name: String; var bytes: Int64; var ageDays: Int }
enum Clean {
 static func scanCaches() -> [Entry] {
  [Entry(path: "/scratch/a", name: "a", bytes: 100, ageDays: 31),
   Entry(path: "/scratch/b", name: "b", bytes: 200, ageDays: 31)]
 }
 static func filtered(_ e: [Entry], match: String?, olderThan: Int?) -> [Entry] { e }
}
class FileManager {
 static let `default` = FileManager()
 func trashItem(at: URL, resultingItemURL: UnsafeMutablePointer<NSURL?>?) throws {
  trace("trash " + at.path)
  if at.lastPathComponent == "b" { throw ValidationError("injected partial failure") }
 }
}
let mode = CommandLine.arguments[1]
let dryRun = mode == "dry", yes = mode == "yes", limit = 2
let match: String? = nil, olderThan: Int? = nil
func command() throws {
''' + method + "\n}\ntry command()\n"


def camera_source(root: Path, source: str) -> str:
    start = source.index("session.startRunning()")
    end = source.index("guard let pixelBuffer", start)
    return prelude(root) + r'''
struct Session {
 func startRunning() { trace("camera-started") }
 func stopRunning() { trace("camera-stopped") }
}
struct Grabber {
 func firstFrame(timeout: Double) -> Int? { CommandLine.arguments[1] == "frame" ? 1 : nil }
}
enum CameraError { static let noFrame = "no frame" }
extension String { var description: String { self } }
let session = Session(), grabber = Grabber(), timeout = 0.01
func command() {
''' + source[start:end] + '\ntrace("saved \\(sample)")\n}\ncommand()\n'


def awake_source(root: Path, source: str) -> str:
    method = body(source, "func run() throws")
    return prelude(root) + r'''
typealias IOPMAssertionID = UInt32
typealias IOPMAssertionLevel = UInt32
typealias CFString = String
let kIOPMAssertionTypePreventUserIdleDisplaySleep = "display"
let kIOPMAssertionTypePreventUserIdleSystemSleep = "system"
let kIOPMAssertionLevelOn: UInt32 = 1, kIOReturnSuccess: Int32 = 0
func IOPMAssertionCreateWithName(_ t: String, _ l: UInt32, _ n: String, _ id: inout UInt32) -> Int32 {
 trace("assertion-acquired"); id = 1; return 0
}
func IOPMAssertionRelease(_ id: UInt32) { trace("assertion-released") }
let display = false, whilePid: Int32? = nil
let duration: Double? = CommandLine.arguments[1] == "duration" ? 0.01 : nil
func command() throws {
''' + method + "\n}\ntry command()\n"


def index_source(root: Path, source: str) -> str:
    declarations = [block(source, marker) for marker in (
        "struct FileIndex:", "struct AgentsIndex:", "private static func readTail(",
        "private static func coveredBytes(", "private static func claudeTokens(",
        "private static func codexTokens(", "private static func scanFile(")]
    methods = "\n".join(declarations).replace("private static func", "static func")
    return r'''import Foundation
enum Agents {
 static let byteBudget: Int64 = 250_000_000
''' + methods + r'''
 static func exercise() throws {
  let dir = URL(fileURLWithPath: CommandLine.arguments[1])
  let file = dir.appendingPathComponent("fixture.jsonl")
  func codex(_ n: Int) -> String {
   "{\"type\":\"token_count\",\"payload\":{\"info\":{\"total_token_usage\":{\"total_tokens\":\(n)}}}}\n"
  }
  var index = AgentsIndex(), bytes: Int64 = 0, truncated = false
  func scan(_ parse: (Data.SubSequence) -> Int64) throws -> Int64 {
   let data = try Data(contentsOf: file)
   let r = scanFile(file, size: Int64(data.count), mtime: Date(timeIntervalSince1970: Double(data.count)),
                    index: &index, reindex: false, bytesRead: &bytes, truncated: &truncated, parse: parse)
   return r.tokens
  }
  try Data(codex(10).utf8).write(to: file)
  let first = try scan(codexTokens)
  try Data((codex(10) + codex(15)).utf8).write(to: file)
  let appended = try scan(codexTokens)
  let unchanged = try scan(codexTokens)
  print("codex first=\(first) appended=\(appended) unchanged=\(unchanged)")
  index = AgentsIndex()
  let rescanned = try scan(codexTokens)
  print("codex reindexed=\(rescanned)")
  index = AgentsIndex()
  func claude(_ n: Int) -> String { "{\"message\":{\"usage\":{\"input_tokens\":\(n)}}}\n" }
  let full = claude(7) + claude(9)
  let partial = claude(7) + String(claude(9).dropLast(3))
  try Data(partial.utf8).write(to: file)
  let before = try scan(claudeTokens)
  try Data(full.utf8).write(to: file)
  let completed = try scan(claudeTokens)
  print("claude partial=\(before) completed=\(completed)")
 }
}
try Agents.exercise()
'''


def fans_source(root: Path, source: str) -> str:
    method = body(block(source, "struct Set:"), "func run() throws")
    return prelude(root) + r'''
struct Fan { var rpm = 3000.0, minRpm = 1000.0, maxRpm = 6000.0; var index = 0 }
enum Fans {
 static func all() -> [Fan] { [Fan()] }
 static func setForcedBit(fan: Int, on: Bool) -> Bool { trace("forced-on"); return true }
 static func targetKey(_ fan: Int) -> String { "F0Tg" }
}
enum SMC {
 static func writeNumber(_ key: String, _ n: Double) -> Bool { trace("target-write"); return mode != "write-fails" }
 static func readFloat(_ key: String) -> Double? { mode == "ignored" ? 3500 : 3000 }
 static func fans() -> [Fan] { [Fan()] }
}
enum Thread { static func sleep(forTimeInterval: Double) {} }
let mode = CommandLine.arguments[1], fan = 0, rpm = 3000
let force = false, yes = mode != "unconfirmed"
func command() throws {
''' + method + "\n}\ntry command()\n"


def screen_source(root: Path, source: str) -> str:
    methods = "\n".join(block(source, marker) for marker in (
        "private func stopCapture(", "private func finishWriting(",
        "func stream(_ stream: SCStream, didOutputSampleBuffer"))
    return r'''import Foundation
typealias CMTime = Int
typealias CMSampleBuffer = Int
func CMSampleBufferDataIsReady(_ n: Int) -> Bool { true }
func CMSampleBufferGetPresentationTimeStamp(_ n: Int) -> Int { n }
enum SCStreamOutputType { case screen }
enum ScreenRecorderError: Error { case writerFailed(String) }
enum Status { case writing, completed, failed }
enum Wait { case success, timedOut }
class DispatchSemaphore {
 var signaled = false
 init(value: Int) {}
 func signal() { signaled = true }
 func wait(timeout: Double) -> Wait { signaled ? .success : .timedOut }
}
extension Double { static func now() -> Double { 0 } }
class SCStream { func stopCapture(_ callback: (Error?) -> Void) {} }
class Input {
 var finished = false
 var isReadyForMoreMediaData: Bool { true }
 func markAsFinished() { finished = true; print("input-finished") }
 func append(_ sample: Int) -> Bool {
  print(finished ? "append-after-finish" : "frame-appended"); return !finished
 }
}
class Writer {
 var status = Status.writing
 var error: NSError? = nil
 func startSession(atSourceTime: Int) {}
 func finishWriting(_ callback: () -> Void) { status = .completed; print("finish-requested"); callback() }
}
class Harness {
 let lock = NSLock(), input = Input(), writer = Writer()
 var sessionStarted = false, frames = 0
 var firstPTS: Int?, lastPTS: Int?, failure: Error?
''' + methods + r'''
 func exercise() {
  let s = SCStream()
  stream(s, didOutputSampleBuffer: 1, of: .screen)
  stopCapture(s)
  // The injected stream has not acknowledged stop. Its frame queue remains live.
  do { try finishWriting() } catch { print("finalize-timeout") }
  stream(s, didOutputSampleBuffer: 2, of: .screen)
 }
}
Harness().exercise()
'''


def terminal_source(root: Path, source: str) -> str:
    callbacks = source[source.index("private nonisolated(unsafe) var _tuiResized"):source.index("enum TUI {")]
    return prelude(root) + callbacks + block(source, "enum TUI {") + r'''
TUI.runInteractive(refresh: 0.01, render: { "READY" }, onKey: { $0 != .quit })
'''


def terminal_check(binary: Path, fatal: bool) -> bool:
    master, slave = pty.openpty()
    original = termios.tcgetattr(slave)
    p = subprocess.Popen([str(binary)], stdin=slave, stdout=slave, stderr=slave)
    seen = b""
    try:
        until = time.monotonic() + 5
        while b"READY" not in seen and time.monotonic() < until:
            if select.select([master], [], [], 0.1)[0]:
                seen += os.read(master, 65536)
        require(b"READY" in seen, "terminal replay never entered its UI")
        if fatal:
            p.send_signal(signal.SIGTERM)
        else:
            os.write(master, b"q")
        p.wait(timeout=5)
        while select.select([master], [], [], 0.05)[0]:
            seen += os.read(master, 65536)
        restored = termios.tcgetattr(slave)
        expected_status = p.returncode != 0 if fatal else p.returncode == 0
        return (expected_status and restored == original
                and b"\x1b[?25h\x1b[?1049l" in seen)
    finally:
        if p.poll() is None:
            p.kill()
            p.wait()
        os.close(master)
        os.close(slave)


CASES = {
    "dmg-install": ("Commands/Dmg.swift", dmg_source,
                    'Out.confirm("Install \\(appName) → \\(dest)?", yes: yes)',
                    'Out.confirm("Install \\(appName) → \\(dest)?", yes: true)'),
    "file-operations": ("Commands/Clean.swift", files_source,
                        "if dryRun {", "if false {"),
    "camera-capture": ("Commands/Camera.swift", camera_source,
                       "defer { session.stopRunning() }", "defer { }"),
    "keep-awake": ("Commands/Awake.swift", awake_source,
                   "defer { IOPMAssertionRelease(assertion) }", "defer { }"),
    "usage-index": ("Commands/Agents.swift", index_source,
                    "offset = e.parsedBytes", "offset = e.size"),
    "fan-control": ("Commands/Fans.swift", fans_source,
                    "guard abs(target - Double(rpm)) <= 2 else {", "guard true else {"),
    "screen-recording": ("Core/ScreenRecorder.swift", screen_source,
                         "if failure != nil { return }", "if false { return }"),
    "terminal-session": ("TUI/TUI.swift", terminal_source,
                         "termiosSaved = true", "termiosSaved = false"),
}


def observations(name: str, binary: Path, folder: Path) -> tuple[dict, bool]:
    if name == "dmg-install":
        results = {mode: run(binary, mode) for mode in
                   ("unconfirmed", "no-app", "copy-fails", "cleanup-fails", "ok")}
        require("TRACE detach" in results["ok"][1], "DMG success must detach")
        require("TRACE detach" not in results["no-app"][1], "expected mounted-image exit finding changed")
        require("TRACE remove /scratch/Applications/Demo.app" in results["copy-fails"][1],
                "expected replacement-loss finding changed")
        require("TRACE detach" not in results["copy-fails"][1], "expected failed-copy exit finding changed")
        require(results["cleanup-fails"][0] == 0 and "dmg removed" in results["cleanup-fails"][1],
                "expected cleanup-report finding changed")
        caught = "TRACE remove" not in results["unconfirmed"][1] and results["unconfirmed"][0] != 0
    elif name == "file-operations":
        results = {mode: run(binary, mode) for mode in ("dry", "no", "yes")}
        require("TRACE trash" not in results["no"][1], "unconfirmed cleanup touched files")
        require("trashed 1 entries" in results["yes"][1] and "1 failed" in results["yes"][1],
                "cleanup partial-failure accounting changed")
        caught = "TRACE trash" not in results["dry"][1] and results["dry"][0] == 0
    elif name == "camera-capture":
        results = {mode: run(binary, mode) for mode in ("frame", "timeout")}
        require(results["timeout"][0] != 0 and "camera-stopped" not in results["timeout"][1],
                "expected camera exit/defer finding changed")
        caught = "camera-stopped" in results["frame"][1]
    elif name == "keep-awake":
        results = {"duration": run(binary, "duration")}
        p = subprocess.Popen([str(binary), "signal"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            # Wait for acquisition before delivering SIGINT; avoid startup races.
            acquired = p.stderr.readline()
            require(b"assertion-acquired" in acquired, "awake did not acquire assertion")
            # SIGINT is installed after the human mode message.
            mode_line = p.stderr.readline()
            time.sleep(0.05)
            p.send_signal(signal.SIGINT)
            try:
                out, err = p.communicate(timeout=0.6)
                raise RuntimeError(f"awake SIGINT finding changed: {out!r} {err!r}")
            except subprocess.TimeoutExpired:
                p.kill()
                out, err = p.communicate(timeout=5)
            results["interrupt"] = (p.returncode, (acquired + mode_line + out + err).decode())
        finally:
            if p.poll() is None:
                p.kill()
                p.wait()
        caught = "assertion-released" in results["duration"][1]
    elif name == "usage-index":
        fixture = folder / "transcripts"
        fixture.mkdir()
        results = {"index": run(binary, str(fixture))}
        require("codex first=10 appended=25 unchanged=25" in results["index"][1],
                "expected cumulative-count finding changed")
        require("codex reindexed=15" in results["index"][1],
                "full Codex reindex must restore the maximum")
        caught = "claude partial=7 completed=16" in results["index"][1]
    elif name == "fan-control":
        results = {mode: run(binary, mode) for mode in ("unconfirmed", "write-fails", "ignored", "ok")}
        require("forced-on" not in results["unconfirmed"][1], "unconfirmed hardware write")
        require("forced-on" in results["write-fails"][1] and "forced-off" not in results["write-fails"][1],
                "expected forced-mode rollback finding changed")
        caught = results["ignored"][0] != 0 and "firmware is managing" in results["ignored"][1]
    elif name == "screen-recording":
        results = {"late-frame": run(binary)}
        require("append-after-finish" in results["late-frame"][1], "late-frame finding changed")
        # Test the failure guard independently of stop/finalization.
        guard_source = binary.parent.joinpath("main.swift").read_text()
        guard_source = guard_source.replace("Harness().exercise()", r'''
let h = Harness()
h.failure = NSError(domain: "fixture", code: 1)
h.stream(SCStream(), didOutputSampleBuffer: 1, of: .screen)
print("frames=\(h.frames)")
''')
        guard_binary = compile_swift(folder / "failed-stream", guard_source)
        results["failure-guard"] = run(guard_binary)
        caught = "frames=0" in results["failure-guard"][1]
    else:
        results = {"quit": terminal_check(binary, False), "sigterm": terminal_check(binary, True)}
        caught = all(results.values())
    return results, caught


def replay(root: Path, scratch: Path, name: str, mutations: bool) -> dict:
    relative, make, old, new = CASES[name]
    source = (root / "Sources/vorssaint" / relative).read_text()
    folder = scratch / f"replay-{name}"
    binary = compile_swift(folder, make(root, source))
    results, intact = observations(name, binary, folder)
    require(intact, f"{name}: baseline regression guard failed")
    receipt = {"baseline": results}
    if mutations:
        mutated = change(source, old, new)
        mutant = compile_swift(folder / "mutant", make(root, mutated))
        mutation_results, still_intact = observations(name, mutant, folder / "mutant")
        require(not still_intact, f"{name}: source mutation was not caught")
        receipt.update(mutation={"old": old, "new": new, "caught": True},
                       mutant=mutation_results)
        restored = folder / "restored"
        restored.mkdir()
        restored_results, intact_again = observations(name, binary, restored)
        require(intact_again, f"{name}: original source replay did not recover")
        receipt["restored_baseline"] = restored_results
    (folder / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return {"baseline": "replayed", "mutation": "caught" if mutations else "not run"}
