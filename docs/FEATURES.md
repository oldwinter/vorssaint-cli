# Vorssaint feature inventory → CLI/TUI classification

Source: `vorssaint/vorssaint-utils` (macOS menu bar toolkit, ~263k LOC Swift, 46 service modules).
This document classifies every feature by whether it belongs in a CLI, a TUI, or must stay in the GUI app.

**Legend**

- `cli` — one-shot, scriptable, exits; safe for agents
- `tui` — interactive full-screen terminal UI on top of the same core
- `gui` — inherently needs AppKit/menu bar/event-tap daemon; out of scope for this CLI
- `daemon` — requires a long-running background process; out of scope for a stateless CLI (v0)

## Sound

| Feature | Class | CLI surface | Notes |
|---|---|---|---|
| Volume mixer (per-app volume, boost) | cli+tui | `volume get/set/mute`, `volume --app` | Per-app volume via CoreAudio; boost uses per-process gain |
| Per-app output routing | cli | `volume route --app <a> --device <d>` | Planned |
| Output switcher | cli | `volume devices`, `volume output <device>` | Auto-lower-on-disconnect is daemon → gui |
| Microphone tools | cli | `mic get/set/mute` | Input level/mute via CoreAudio |
| Music app blocker | daemon | — | Needs launch-watch daemon |

## System monitoring

| Feature | Class | CLI surface | Notes |
|---|---|---|---|
| System monitor (cpu/gpu/mem/temps/battery/energy) | cli+tui | `monitor cpu|mem|disk|net|battery`, `top` | `--watch` = TUI dashboard |
| Fan control | cli | `sensors fans`, `fans set` | Read via IOKit/SMC; set is planned (SMC write) |
| Menu bar readouts | gui | — | Menu bar only |
| Network (traffic, totals, IP, speed test) | cli | `net`, `ip`, `speedtest` | `networkQuality` for speed test |
| Alerts | daemon | — | One-shot equivalents live under `doctor` |

## Windows & Dock

| Feature | Class | CLI surface | Notes |
|---|---|---|---|
| App switcher | tui | `switch` | Live previews stay gui; list-switcher is tui |
| Window layout / snap | cli | `window snap|zoom|list` | Needs Accessibility permission |
| Dock Preview | gui | — | |
| Dock click behaviors | gui | — | Persistent preference, set via `settings` |
| Maximize (green button zoom) | cli | `window zoom` | Needs Accessibility |
| Fixed Space order | cli | `spaces lock-order|unlock-order` | `defaults com.apple.dock mru-spaces` |
| Quit on close | daemon | — | |
| Quit/close protection | daemon | — | Event-tap daemon |

## Keyboard & mouse

| Feature | Class | CLI surface | Notes |
|---|---|---|---|
| Text snippets | cli+tui | `snip list|add|expand|remove` | Expansion into apps needs paste; `expand` prints/copies |
| Smooth scrolling / linear scrolling | daemon | — | Event-tap daemons |
| Pointer acceleration off | cli | `mouse acceleration on|off` | `defaults` + note about relogin |
| Focus follows mouse | daemon | — | |
| Scroll direction / sideways / side buttons / button shortcuts / middle click / click filter | daemon | — | Event-tap daemons |
| Key debounce | daemon | — | |
| Super key | daemon | — | |
| App exclusion lists | cli | `settings` (config file) | Config only |
| Shortcut management | gui | — | |

## Clipboard, files, links

| Feature | Class | CLI surface | Notes |
|---|---|---|---|
| Clipboard history | daemon+tui | `clip get/set/clear` | History recording needs daemon → planned |
| Auto clear clipboard | cli | `clip clear` | One-shot; timed clearing is daemon |
| Paste as plain text | cli | `clip set --plain`, `clip get --plain` | |
| Shelf | gui | — | Drag/drop UI |
| Finder shortcuts | daemon | — | |
| Clean URL | cli | `url clean <url>` | Pure function, great for pipes |
| Disk image installer | cli | `dmg install <file.dmg>` | hdiutil + copy + eject |

## Everyday tools

| Feature | Class | CLI surface | Notes |
|---|---|---|---|
| Dynamic Island | gui | — | |
| AI agents usage | cli | `agents` | Local Claude/Codex/OpenCode jsonl scan (no network) |
| Command Bar | tui | `find`/`open` + `snip pick` | Fuzzy launcher subset |
| Quick panel | gui | — | |
| Quick toggles (appearance, desktop icons, eject, trash, lock) | cli | `appearance`, `desktop-icons`, `eject`, `trash`, `lock` | All one-shot |
| Quit apps | cli+tui | `apps list|quit|quit-all|quit-others` | |
| Radial menu | gui | — | |
| Scratchpad | cli | `note` (planned) | Plain markdown files |
| Cleaning Mode | gui | — | |

## Capture & create

| Feature | Class | CLI surface | Notes |
|---|---|---|---|
| Screenshot | cli | `shot --screen|--window|--area` | screencapture/ScreenCaptureKit |
| Screenshot annotate/edit | gui | — | Editor stays gui |
| Screen recording | cli | `record start|stop` (planned) | ScreenCaptureKit; editing → `media` |
| Camera preview | gui | — | `camera shot` (planned) can grab a frame |
| OCR from screen | cli | `ocr --screen|--image` | Vision, offline — very agent-useful |
| Color picker | cli | `color at <x> <y>` / `pick` | |
| Media tools (info/convert/gif/compress) | cli | `media ...` | sips + ffmpeg |

## App management

| Feature | Class | CLI surface | Notes |
|---|---|---|---|
| App updates | cli | `apps outdated` (brew part live) | Store updates via `mas`/`softwareupdate` |
| Cleaner | cli | `clean scan|run` | Moves to Trash (recoverable), `--dry-run` |
| Messaging downloads | cli | `downloads list|organize` | Planned |
| Uninstaller | cli | `apps uninstall <app>` | Finds app + related files → Trash, `--dry-run` |
| Homebrew manager | cli+tui | `brew ...` | Thin structured wrapper over `brew --json` |
| Port manager | cli+tui | `ports list|kill` | lsof-backed |

## Energy & display

| Feature | Class | CLI surface | Notes |
|---|---|---|---|
| Keep awake | cli | `awake [--for|--while]` | IOPMAssertion / caffeinate semantics |
| Displays / brightness | cli | `display list|brightness` | DDC/planned for external monitors |
| Extra brightness (XDR) | cli | `display boost` | Planned (private API) |
| Bluetooth on sleep | daemon | — | `bluetooth on|off` is cli |

## Existing hidden flags → first-class commands

| Legacy flag | New command |
|---|---|
| `--export-settings <p>` / `--import-settings <p>` | `settings export|import` |
| `--selftest` | `doctor` |
| `--sensors` | `sensors` |
| `--uninstall` | (handled by package manager) |
| `--mouse-acceleration-cleanup` | internal helper — not exposed |

## Agent-friendliness contract

Every command:

- `--json` — machine output: `{ "ok": true, "command": "...", "data": … }`; errors → `{ "ok": false, "error": { "code", "message" } }` on stderr with non-zero exit
- `--plain` — no color/tables, newline/tab separated
- Exit codes: `0` ok · `1` runtime error · `2` usage · `3` not implemented · `4` permission · `5` not found
- No prompts in non-TTY or under `--json`/`--plain`; `--yes` confirms destructive ops; `--dry-run` previews them
- `vorssaint features --json` is the machine-readable capability catalog (status per command)
- `vorssaint doctor` reports permission/env state (screen recording, accessibility, brew, ffmpeg…) so an agent can self-diagnose
