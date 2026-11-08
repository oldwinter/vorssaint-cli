// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ArgumentParser
import CoreAudio
import Foundation

struct VolumeState: Encodable {
    var percent: Int, muted: Bool, device: String, deviceUID: String
}

struct Volume: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Output volume, mute and audio devices",
        subcommands: [Get.self, Set.self, Mute.self, Unmute.self, Devices.self, Output.self, Route.self],
        defaultSubcommand: Get.self
    )

    private static func state() -> VolumeState? {
        guard let dev = AudioHAL.defaultDevice(.output) else { return nil }
        let v = AudioHAL.volume(dev, scope: .output) ?? 0
        return VolumeState(percent: Int((v * 100).rounded()), muted: AudioHAL.muted(dev, scope: .output) ?? false,
                           device: AudioHAL.name(dev), deviceUID: AudioHAL.uid(dev))
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show current output volume")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint volume")
            guard let s = state() else { Out.fail("no_device", "no default output device", exit: .notFound) }
            Out.emit(s) { "\(s.percent)%\(s.muted ? " (muted)" : "") — \(s.device)" }
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Set output volume 0–100 (or 0–150 on devices that support boost)")
        @OptionGroup var g: GlobalOptions
        @Argument(help: "Volume percent 0–150") var percent: Int
        func run() throws {
            wireOutput(g, command: "vorssaint volume set")
            guard (0...150).contains(percent) else { throw ValidationError("percent must be 0–150") }
            guard let dev = AudioHAL.defaultDevice(.output) else { Out.fail("no_device", "no default output device", exit: .notFound) }
            let target = Float(percent) / 100
            guard AudioHAL.setVolume(dev, scope: .output, target) else {
                Out.fail("set_failed", "could not set volume on \(AudioHAL.name(dev)) (device may not support software volume)")
            }
            Out.emit(state()!) { "volume → \(percent)% (\(AudioHAL.name(dev)))" }
        }
    }

    struct Mute: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Mute output")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint volume mute")
            guard let dev = AudioHAL.defaultDevice(.output) else { Out.fail("no_device", "no default output device", exit: .notFound) }
            _ = AudioHAL.setMuted(dev, scope: .output, true)
            Out.emit(state()!) { "muted (\(AudioHAL.name(dev)))" }
        }
    }

    struct Unmute: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Unmute output")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint volume unmute")
            guard let dev = AudioHAL.defaultDevice(.output) else { Out.fail("no_device", "no default output device", exit: .notFound) }
            _ = AudioHAL.setMuted(dev, scope: .output, false)
            Out.emit(state()!) { "unmuted (\(AudioHAL.name(dev)))" }
        }
    }

    struct Devices: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List audio devices")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint volume devices")
            let devs = AudioHAL.devices()
            if Out.json { Out.emit(devs) { "" } }
            else {
                Out.table(["ID", "NAME", "DIRS", "DEFAULT"], rows: devs.map {
                    [String($0.id), $0.name, [ $0.isOutput ? "out" : nil, $0.isInput ? "in" : nil ].compactMap { $0 }.joined(separator: "+"),
                     [ $0.isDefaultOutput ? "output" : nil, $0.isDefaultInput ? "input" : nil ].compactMap { $0 }.joined(separator: "+")]
                })
            }
        }
    }

    struct Output: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Switch default output device (by name, uid or id)")
        @OptionGroup var g: GlobalOptions
        @Argument(help: "Device name substring, uid, or id") var device: String
        func run() throws {
            wireOutput(g, command: "vorssaint volume output")
            guard let dev = AudioHAL.findDevice(device, scope: .output) else {
                Out.fail("not_found", "no output device matching '\(device)' — see `vorssaint volume devices`", exit: .notFound)
            }
            guard AudioHAL.setDefaultDevice(.output, dev) else {
                Out.fail("set_failed", "could not switch output to \(AudioHAL.name(dev))")
            }
            Out.emit(state()!) { "output → \(AudioHAL.name(dev))" }
        }
    }

    struct Route: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show or set per-app output routing",
            discussion: """
            Uses the public CoreAudio process-object API. Listing and reading are
            supported everywhere; changing another app's routing is attempted and
            verified by reading it back — macOS may reject the write.

              vorssaint volume route
              vorssaint volume route --app Safari
              vorssaint volume route --app Safari --device "MacBook Speakers"
            """
        )
        @OptionGroup var g: GlobalOptions
        @Option(help: "App name, bundle id or pid (omit to list audio processes)") var app: String?
        @Option(help: "Output device name, uid or id (omit to show only)") var device: String?

        struct Entry: Encodable {
            var pid: Int32, name: String, bundleID: String
            var deviceIDs: [UInt32], devices: [String]
        }

        static func entry(_ p: AudioHAL.Process) -> Entry {
            Entry(pid: p.pid,
                  name: NSRunningApplication(processIdentifier: p.pid)?.localizedName ?? "",
                  bundleID: p.bundleID, deviceIDs: p.outputDevices,
                  devices: p.outputDevices.map { AudioHAL.name(AudioObjectID($0)) })
        }

        static func find(_ query: String) -> AudioHAL.Process? {
            let all = AudioHAL.processes()
            if let pid = Int32(query) { return all.first { $0.pid == pid } }
            let q = query.lowercased()
            return all.first { $0.bundleID.lowercased() == q }
                ?? all.first { $0.bundleID.lowercased().contains(q) }
                ?? all.first {
                    (NSRunningApplication(processIdentifier: $0.pid)?.localizedName ?? "")
                        .lowercased().contains(q)
                }
        }

        func run() throws {
            wireOutput(g, command: "vorssaint volume route")
            if app == nil {
                let all = AudioHAL.processes().map(Self.entry).sorted { $0.pid < $1.pid }
                if Out.json { Out.emit(all) { "" } }
                else {
                    Out.table(["PID", "APP", "BUNDLE", "OUTPUT"], rows: all.map {
                        [String($0.pid), $0.name.isEmpty ? "-" : $0.name,
                         $0.bundleID.isEmpty ? "-" : $0.bundleID,
                         $0.devices.isEmpty ? "-" : $0.devices.joined(separator: ", ")]
                    })
                }
                return
            }
            guard let query = app, let proc = Self.find(query) else {
                Out.fail("not_found",
                         "no audio process matching '\(app ?? "")' — run `vorssaint volume route` to list them",
                         exit: .notFound)
            }
            let before = Self.entry(proc)
            let label = before.name.isEmpty ? before.bundleID : before.name
            guard let device else {
                if Out.json { Out.emit(before) { "" } }
                else {
                    print("\(label) (pid \(before.pid)) → "
                        + (before.devices.isEmpty ? "system default" : before.devices.joined(separator: ", ")))
                }
                return
            }
            guard let dev = AudioHAL.findDevice(device, scope: .output) else {
                Out.fail("not_found", "no output device matching '\(device)' — see `vorssaint volume devices`", exit: .notFound)
            }
            let wrote = AudioHAL.setProcessDevices(AudioObjectID(proc.id), scope: .output, [dev])
            let after = Self.entry(AudioHAL.processes().first { $0.id == proc.id } ?? proc)
            guard wrote, after.deviceIDs.contains(UInt32(dev)) else {
                Out.fail("unsupported",
                         "macOS did not accept routing \(label) to \(AudioHAL.name(dev)) — the public process API is read-only for other apps' audio (per-app routing needs the private kAudioHardwareServiceProcessObjectID path, not implemented)",
                         exit: .notImplemented)
            }
            struct R: Encodable { var app: String, pid: Int32, device: String, deviceID: UInt32 }
            Out.emit(R(app: label, pid: before.pid, device: AudioHAL.name(dev), deviceID: dev)) {
                "\(label) → \(AudioHAL.name(dev))"
            }
        }
    }
}

struct Mic: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Microphone input level and mute",
        subcommands: [Get.self, Set.self, Mute.self, Unmute.self],
        defaultSubcommand: Get.self
    )

    private static func state() -> VolumeState? {
        guard let dev = AudioHAL.defaultDevice(.input) else { return nil }
        return VolumeState(percent: Int(((AudioHAL.volume(dev, scope: .input) ?? 0) * 100).rounded()),
                           muted: AudioHAL.muted(dev, scope: .input) ?? false,
                           device: AudioHAL.name(dev), deviceUID: AudioHAL.uid(dev))
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show input level")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint mic")
            guard let s = state() else { Out.fail("no_device", "no default input device", exit: .notFound) }
            Out.emit(s) { "\(s.percent)%\(s.muted ? " (muted)" : "") — \(s.device)" }
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Set input level 0–100")
        @OptionGroup var g: GlobalOptions
        @Argument var percent: Int
        func run() throws {
            wireOutput(g, command: "vorssaint mic set")
            guard (0...100).contains(percent) else { throw ValidationError("percent must be 0–100") }
            guard let dev = AudioHAL.defaultDevice(.input) else { Out.fail("no_device", "no default input device", exit: .notFound) }
            guard AudioHAL.setVolume(dev, scope: .input, Float(percent) / 100) else {
                Out.fail("set_failed", "input level not adjustable on \(AudioHAL.name(dev))")
            }
            Out.emit(state()!) { "mic → \(percent)% (\(AudioHAL.name(dev)))" }
        }
    }

    struct Mute: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Mute microphone")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint mic mute")
            guard let dev = AudioHAL.defaultDevice(.input) else { Out.fail("no_device", "no default input device", exit: .notFound) }
            _ = AudioHAL.setMuted(dev, scope: .input, true)
            Out.emit(state()!) { "mic muted (\(AudioHAL.name(dev)))" }
        }
    }

    struct Unmute: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Unmute microphone")
        @OptionGroup var g: GlobalOptions
        func run() throws {
            wireOutput(g, command: "vorssaint mic unmute")
            guard let dev = AudioHAL.defaultDevice(.input) else { Out.fail("no_device", "no default input device", exit: .notFound) }
            _ = AudioHAL.setMuted(dev, scope: .input, false)
            Out.emit(state()!) { "mic unmuted (\(AudioHAL.name(dev)))" }
        }
    }
}
