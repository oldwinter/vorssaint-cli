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

### install.sh

```sh
curl -fsSL https://raw.githubusercontent.com/oldwinter/vorssaint-cli/master/install.sh | sh
```

Fetches the latest release, verifies its sha256 and architecture, clears the
quarantine attribute, and installs to `/usr/local/bin` when writable, otherwise
`~/.local/bin`. Pin a version with `--version vX.Y.Z`, choose a directory with
`--prefix DIR`, or set `VORSSAINT_VERSION` / `VORSSAINT_INSTALL_DIR`.

### Homebrew

The formula lives in [`Formula/vorssaint.rb`](Formula/vorssaint.rb) and is
published to [`oldwinter/homebrew-tap`](https://github.com/oldwinter/homebrew-tap).
Until the first tagged release it builds from source:

```sh
brew install --HEAD oldwinter/tap/vorssaint
```

After the first release it installs the release binary:

```sh
brew install oldwinter/tap/vorssaint
```

Releases regenerate the stable formula with
`scripts/release-formula.sh vX.Y.Z` (`TAP_DIR=../homebrew-tap` also copies it
into a tap checkout).

### From source

```sh
git clone https://github.com/oldwinter/vorssaint-cli.git && cd vorssaint-cli
swift build -c release
install -m 0755 "$(swift build -c release --show-bin-path)/vorssaint" ~/.local/bin/
```

Requires macOS 14+, Apple Silicon or Intel, Swift 6 toolchain (Xcode 16+; CLT is enough).

### Shell completions

`swift-argument-parser` generates completions for zsh, bash and fish:

```sh
# zsh — must land in a directory from $fpath
vorssaint --generate-completion-script zsh > "${fpath[1]}/_vorssaint"

# bash
vorssaint --generate-completion-script bash > ~/.local/share/bash-completion/completions/vorssaint

# fish
vorssaint --generate-completion-script fish > ~/.config/fish/completions/vorssaint.fish
```

CI regenerates all three on every build so a broken command tree cannot slip in.

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
                 fans list|set <rpm>|auto          SMC fan readout & manual target
                 top                              live TUI dashboard (q quits)
AUDIO            volume get|set|mute|unmute|devices|output
                 volume route [--app A] [--device D]  per-app output routing
                 mic get|set|mute|unmute
APPS & PORTS     apps list|quit|quit-all|quit-others|open|uninstall
                 switch                           TUI app switcher (↑↓ Enter q)
                 window list|snap <preset>|zoom   AX window layout
                 ports list|kill <port>
FILES & CLIP     clip get|set|clear               images: get --image / set --image f.png
                 downloads list|organize          ~/Downloads by source/age/type, tidy by type
                 note [text]|list|show|edit       markdown scratchpad in ~/.config/vorssaint/notes
                 url clean <url>...
                 trash list|empty [--dry-run]     eject [list|volume|all]
                 dmg install <file.dmg>           snip list|add|expand|remove
                 clean scan|run [--older-than N]  cache cleaner → Trash
CAPTURE          shot [--area|--window|--clipboard|--delay N] out.png
                 record [out.mov|out.mp4] [--duration N] [--display ID]
                 camera list|shot [out.png] [--device ID]   AVCapture single frame
                 ocr --image|--screen|--clipboard color at <x> <y>|convert <c>
                 media info|convert|gif|compress  sips / ffmpeg tools
AGENTS           agents                           Claude/Codex/OpenCode tokens
SYSTEM           awake [--for S|--while PID|--display]
                 display list|brightness [set N]|boost|ddc
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
vorssaint volume route --app Safari --device "MacBook Speakers"
vorssaint display boost --amount 1.4           # XDR built-in panels only
vorssaint fans set 3000 --fan 0 --yes          # verified SMC write, clamped
vorssaint camera shot /tmp/me.png              # single AVCapture frame
vorssaint snip add today "{{date}} standup:" && vorssaint snip expand today --copy
vorssaint note "ship the release notes"        # appends to today's note
vorssaint downloads organize --dry-run         # preview, then --yes to apply
vorssaint clip get --image > /tmp/paste.png    # clipboard image round-trip
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

Planned next: clipboard history, native DDC control without a helper. Track
status via `vorssaint features`.

## Permissions

`vorssaint doctor` checks: Screen Recording (shot/record/ocr/color/window
titles), Accessibility (future window layout), Full Disk Access (future
cleaner), Automation (appearance), Camera (camera shot), SMC (fans). Optional
tools: brew, blueutil, ffmpeg, mas, ddcctl/m1ddc.

## Check the state machines

Eight project skills under [`.agents/skills/`](.agents/skills/) cover screen
recording, camera capture, file operations, DMG installation, fan control,
keep-awake, usage indexing, and terminal sessions.

```sh
python3 formal/check.py --mutations
```

The checks use bounded TLA+ models and isolated Swift source replays.
The command exits `1` while recorded violations remain. Read the
[findings and Mermaid flows](formal/REPORT.md), open the
[interactive flow viewer](formal/results/flows.html), or see the
[setup and scope](formal/README.md).

## License

GPL-3.0-or-later, matching the original Vorssaint project.
