---
name: terminal-session
description: "Recheck the terminal session state machine when changing its lifecycle, failure handling, or covered source; run bounded TLC verification and source replay."
---

# Terminal session

Promise: After a normal quit or handled fatal signal from the active dashboard, terminal settings and cursor visibility are restored.

User harm: A failed restore leaves the shell in raw input or hides its cursor.

## Run and decide

1. From the repository root, read the `terminal-session` entry in `formal/coverage.json` and the covered functions below. Compare the model's step boundaries with the current implementation before trusting a result.
2. Run `python3 formal/check.py --subsystem terminal-session --mutations`. The runner pins TLC 1.7.4 by checksum, checks every invariant separately, compiles actual Swift source into isolated replay programs, and checks a matching model mutation. Read the printed scratch directory's `summary.json`, `replay-terminal-session/receipt.json`, and TLC logs. Exit 1 means a recorded finding remains; exit 2 means verification is inconclusive. An unexpected pass also requires review.
3. Use `/statechart` for **every** TLA+ result. Load the installed skill for its current invocation. Copy `formal/models/TerminalSession.tla`, its `.cfg`, and its `.view.mjs` into a fresh scratch directory outside this repository. Read each shortest path in the source's terms; draw the passing graph too. Keep terminal stuttering steps in the model.
4. If a rule fails, replay its action sequence against the covered Swift source with the isolated replay program. If a path does not reproduce, treat the path as a modeling error until evidence resolves it. Preserve actual failures as findings; change product behavior only with user authorization.
5. After an intended implementation change, update the model, replay and scratch mutation together. Rerun the command, review each recorded expectation, then update this skill's synchronization commit and the entry's source hashes. Move the commit forward only after confirming model/source agreement; a hash match alone is not a proof. Use `/maintain-formal-verification-skill` after unverified changes.

## Coverage record

Last source review: 2026-11-11. Synchronization commit: `d91fec94f4641afd646336f1ce128620676c4999`.

- `Sources/vorssaint/TUI/TUI.swift`
- `Sources/vorssaint/Core/Output.swift`

Covered functions and boundaries: `TUI.runInteractive`; `TUI.restoreTerminal`; `TUI.installFailsafe`.

Model: `formal/models/TerminalSession.tla`; configuration and reader-facing view live beside it. Exact source fingerprints, expected findings, and mutation rule live in `formal/coverage.json`.

Bounds and assumptions: One terminal session: piped output, saved settings, raw mode, alternate screen, normal quit, handled fatal signal, idempotent cleanup. The complete TUI enum is compiled from source and tested on real pseudo-terminals with q and SIGTERM; all termios fields and the cursor/alternate-screen restore sequence are compared. SIGKILL, startup signals before failsafe registration, resize and Unicode input are excluded.

Recorded findings: none. The checked paths and their source replay evidence are in `formal/results/` and the runner's scratch receipts.

Negative control: Lose the saved-termios flag; q and SIGTERM must fail restoration. The mutation changes only a scratch copy; the working product source stays intact. The matching model mutation must break `TerminalRestored`. The handoff is complete only after baseline replays succeed, the scratch regression is detected, and baseline checks return to the same finding set.
