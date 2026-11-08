# vorssaint-cli

macOS power tools as a single terminal binary — built for shells, scripts and agents.

A CLI/TUI reimagining of [Vorssaint](https://github.com/vorssaint/vorssaint-utils)
(the 30k-star menu-bar toolkit): every feature that makes sense outside a menu
bar app, behind one `vorssaint` command with a strict agent contract.

- **Agents**: every command takes `--json` (structured envelope) and `--plain`
  (pipe-friendly). Destructive commands require `--yes`, support `--dry-run`,
  and never prompt when stdout isn't a TTY.
- **Humans**: sane defaults, colored output when attached to a terminal,
  `vorssaint top` for a live dashboard.
- **Zero magic**: failures exit non-zero with a coded error; permissions are
  checked up front by `vorssaint doctor`.

## Install

```sh
git clone <repo> && cd vorssaint-cli
swift build -c release
cp .build/release/vorssaint /opt/homebrew/bin/
```

Requires macOS 14+, Apple Silicon or Intel, Swift toolchain (CLT is enough).

## The contract (for agents)

```sh
vorssaint features --json      # capability catalog with status per command
vorssaint doctor               # environment/permission preflight
vorssaint --selftest           # permission-free sanity checks (used by CI)
vorssaint <cmd> --json         # {"ok":true,"command":"...","data":…}
vorssaint <cmd> --json         # error → stderr {"ok":false,"error":{"code","message"}}
```

Exit codes: `0` ok · `1` runtime · `2` usage · `3` not implemented · `4` permission · `5` not found.

## Commands

```
MONITOR          monitor cpu|mem|disk|net|battery|sensors [--watch]
                 top                              live TUI dashboard (q quits)
AUDIO            volume get|set|mute|unmute|devices|output
                 mic get|set|mute|unmute
APPS & PORTS     apps list|quit|quit-all|quit-others|open|uninstall
                 switch                           TUI app switcher (↑↓ Enter q)
                 window list|snap <preset>|zoom   AX window layout
                 ports list|kill <port>
FILES & CLIP     clip get|set|clear               url clean <url>...
                 trash list|empty [--dry-run]     eject [list|volume|all]
                 dmg install <file.dmg>           snip list|add|expand|remove
                 clean scan|run [--older-than N]  cache cleaner → Trash
CAPTURE          shot [--area|--window|--clipboard|--delay N] out.png
                 record [out.mov|out.mp4] [--duration N] [--display ID]
                 ocr --image|--screen|--clipboard color at <x> <y>|convert <c>
                 media info|convert|gif|compress  sips / ffmpeg tools
AGENTS           agents                           Claude/Codex/OpenCode tokens
SYSTEM           awake [--for S|--while PID|--display]
                 display list|brightness [set N]
                 appearance dark|light|toggle     desktop-icons hide|show
                 spaces lock-order|unlock-order   mouse acceleration on|off
                 bluetooth on|off|status          lock
NETWORK          net ip [--public]|rates          speedtest [--sequential]
PACKAGES         brew list|search|info|install|uninstall|outdated|upgrade
META             doctor | features | settings path|export|import
```

Every leaf command has its own `--help`.

## Examples

```sh
vorssaint monitor --json | jq .data.cpu.usedPercent
vorssaint volume set 30 && vorssaint mic mute
vorssaint ports kill 3000 --yes
vorssaint apps quit "Zen" --yes
echo https://x.com/post?utm_source=a&fbclid=b | vorssaint url clean
vorssaint ocr --screen --plain | pbcopy
vorssaint trash empty --dry-run && vorssaint trash empty --yes
vorssaint awake --for 3600 &
vorssaint shot --area /tmp/shot.png
vorssaint record /tmp/demo.mov --duration 10   # ScreenCaptureKit, primary display
vorssaint snip add today "{{date}} standup:" && vorssaint snip expand today --copy
vorssaint brew outdated --json | jq '.formulae | length'
vorssaint window snap left --app Safari   # presets: halves corners thirds fill center cycle; --index/--display
vorssaint apps uninstall "Vorssaint" --dry-run
vorssaint clean run --older-than 30 --yes # stale caches → Trash (recoverable)
vorssaint agents                          # local Claude/Codex token usage
```

## What stays in the GUI (and why)

Event-tap daemons (smooth scrolling, key debounce, super key, quit protection),
drag/drop UI (Shelf, Dynamic Island, radial menu), and menu-bar surfaces can't
be a stateless CLI. The full classification — all 60+ app features mapped to
cli / tui / gui / daemon — lives in [docs/FEATURES.md](docs/FEATURES.md).

Planned next: `downloads` organizer, clipboard history, per-app volume routing. Track status via
`vorssaint features`.

## Permissions

`vorssaint doctor` checks: Screen Recording (shot/ocr/color/window titles),
Accessibility (future window layout), Full Disk Access (future cleaner),
Automation (appearance). Optional tools: brew, blueutil, ffmpeg, mas.

## License

GPL-3.0-or-later, matching the original Vorssaint project.
