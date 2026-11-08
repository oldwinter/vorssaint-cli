// SPDX-License-Identifier: GPL-3.0-or-later
import ArgumentParser
import Foundation

@main
struct Vorssaint: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vorssaint",
        abstract: "macOS power tools, built for terminals and agents.",
        discussion: """
        One binary for the parts of a menu-bar toolkit that make sense in a shell:
        system monitoring, audio, apps, ports, clipboard, screenshots, OCR, URLs,
        sleep/display/appearance toggles, brew, and more.

        Every command supports --json (structured envelope) and --plain
        (script-friendly). Destructive commands take --yes / --dry-run and never
        prompt when stdout is not a TTY.

        Discover the full surface:  vorssaint features --json
        Check your environment:     vorssaint doctor
        """,
        version: "0.1.0",
        subcommands: [
            Monitor.self, Top.self, Fans.self,
            Volume.self, Mic.self,
            Apps.self, Ports.self, WindowCmd.self, Switch.self,
            Brew.self,
            Clip.self,
            Downloads.self, Note.self,
            URLGroup.self,
            Awake.self,
            Display.self, Appearance.self, DesktopIcons.self, Spaces.self,
            MouseCmd.self, Bluetooth.self,
            Lock.self, Trash.self, Eject.self,
            Shot.self, Record.self, Camera.self, Ocr.self, ColorCmd.self,
            Media.self, Clean.self,
            Net.self, Speedtest.self,
            Snip.self, Agents.self,
            Dmg.self,
            Doctor.self, Features.self, Settings.self,
        ],
        defaultSubcommand: nil
    )
}
