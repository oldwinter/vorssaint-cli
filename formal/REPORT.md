# Checked state machines and user flows

Reviewed on 2026-11-11 against source commit `d91fec94f4641afd646336f1ce128620676c4999`. This verification package does not change product source.

Eight subsystem skills, eight finite models, 26 configured rules, and eight scratch Swift regressions with matching model negative controls. Eight rule violations remain visible. The existing Swift suite passed 18 tests.

The checker exits 1 while known findings remain. These results establish the finite models and the recorded source replays; they do not prove framework behavior, physical hardware behavior, or all Swift executions.

## Findings and evidence

| Subsystem | Rule | Shortest source-level path | Evidence and limit |
| --- | --- | --- | --- |
| Screen recording | `NoAppendAfterFinish` | Start → capture a frame → stop request → stop timeout → finalization → late frame | Actual callback/stop/finalize methods with injected late callback and ready input; real ScreenCaptureKit scheduling still needs validation. |
| Camera | `ExplicitStopOnError` | Access granted → start → frame timeout → process exit | Actual start/defer/frame-wait code and actual `Out.fail`; verifies missing explicit stop, not a camera persisting after process teardown. |
| DMG | `ErrorUnmountsImage` | Mount → no app → process exit | Actual command body; fake mount receives no detach call. A real image is never mounted. |
| DMG | `FailedReplacementKeepsOldApp` | Mount → approval → delete old app → copy failure | Actual command body calls destination removal before the failed copy; no restoration. |
| DMG | `CleanupReportIsTrue` | Mount → approval → copy → cleanup failure → success | Actual command body suppresses deletion error and prints “dmg removed”. |
| Fan control | `FailureRestoresAutomatic` | Approval → forced bit enabled → target-write failure | Actual Set.run leaves the fake forced bit set; physical firmware behavior is outside scope. |
| Keep-awake | `InterruptEventuallyReleases` | Acquire assertion → Ctrl-C → repeat indefinitely | Actual run body uses real main-queue signal dispatch and Thread.sleep; fixture assertion remains unreleased until the test child is killed. |
| Usage index | `CumulativeUsageIsMaximum` | Cache total 10 → append cumulative total 15 → total 25 | Actual scanFile/codexTokens over scratch JSONL; unchanged cache stays 25, full reindex models recovery to 15. |

## Running and maintaining the checks

```sh
python3 formal/check.py --mutations
python3 formal/check.py --subsystem dmg-install --mutations
```

The source manifest is [coverage.json](coverage.json); the verifier and replay instructions are in [README.md](README.md). Source changes require reviewing the transition boundaries and deliberately advancing the synchronization record. Use `/maintain-formal-verification-skill` after changes that did not recheck the model.

For visual regeneration, invoke the installed `/statechart` skill with a scratch copy of each model/config/view and a new output directory. Render the resulting Mermaid with Pele 1.9.0. The views hide terminal stuttering actions and merge internal steps that do not change the reader-visible label. In particular, per-item file-move steps stay inside the applying state. The full TLC models retain these transitions.

## Record a screen video

[Subsystem skill](../.agents/skills/screen-recording/SKILL.md) · [TLC report](results/screen-recording/report.md) · [SVG](results/screen-recording/chart.svg) · [Source replay evidence](results/screen-recording/evidence.json)

One stream, one accepted frame, one stream failure, and one late callback; acknowledgement and timeout are distinct. The replay runs actual callback, stop and finish methods with fake framework objects. It does not record a real display or prove ScreenCaptureKit callback timing.

![Checked screen-recording flow](results/screen-recording/chart.svg)

```mermaid
---
title: "Record a screen video"
---
stateDiagram-v2
  state "Legend" as legend {
    lg0: active
    lg1: success
    lg2: bug
    lg3: Breaks NoAppendAfterFinish
    lg4: Path to the NoAppendAfterFinish bug
  }
  class lg0 blue
  class lg1 teal
  class lg2 pink
  class lg3 breaks
  class lg4 bugPath
  s0: You choose a display and output
  s1: Command reports an error
  s2: Waiting for the first frame
  s3: Capture failed#59; waiting to stop
  s4: Recording frames
  s5: Stopping capture
  s6: Stop timed out#59; capture may still be live
  s7: Capture stopped
  s8: Writer finalized
  s9: A late frame reaches the finished writer
  s10: Video saved
  [*] --> s0
  s0 --> s1: screen permission denied
  s0 --> s2: permission granted#59; capture starts
  s2 --> s3: capture reports a failure
  s2 --> s4: a frame arrives
  s2 --> s5: duration ends or you press Ctrl-C
  s3 --> s5: duration ends or you press Ctrl-C
  s4 --> s3: capture reports a failure
  s4 --> s5: duration ends or you press Ctrl-C
  s5 --> s6: stop waits ten seconds and times out
  s5 --> s7: capture confirms it stopped
  s6 --> s8: the video writer finalizes
  s7 --> s8: the video writer finalizes
  s8 --> s1: the command checks frames and failure
  s8 --> s9: an unacknowledged callback arrives [after a captured frame]
  s8 --> s10: the command checks frames and failure
  classDef breaks fill:#ffecee,stroke:#e72e3b,stroke-width:2.5px,color:#cd2834
  class s0 blue
  class s0 bugPath
  class s1 blue
  class s2 blue
  class s2 bugPath
  class s3 blue
  class s4 blue
  class s4 bugPath
  class s5 blue
  class s5 bugPath
  class s6 blue
  class s6 bugPath
  class s7 blue
  class s8 blue
  class s8 bugPath
  class s9 pink
  class s9 breaks
  class s9 bugPath
  class s10 teal
```

## Preview and clean files

[Subsystem skill](../.agents/skills/file-operations/SKILL.md) · [TLC report](results/file-operations/report.md) · [SVG](results/file-operations/chart.svg) · [Source replay evidence](results/file-operations/evidence.json)

Two selected cache entries with independent success/failure. The replay executes the actual cleaner body with a fake filesystem and real output/confirmation logic. Target discovery, app-uninstall matching, Downloads collisions, permanent Trash emptying, settings import and concurrent filesystem replacement are excluded.

![Checked file-operations flow](results/file-operations/chart.svg)

```mermaid
---
title: "Preview and apply file operations"
---
stateDiagram-v2
  state "Legend" as legend {
    lg0: complete
    lg1: active
  }
  class lg0 teal
  class lg1 blue
  s0: Items selected for removal
  s1: You request a dry run
  s2: Waiting for confirmation
  s3: Preview shown#59; files unchanged
  s4: Cancelled#59; files unchanged
  s5: Moving selected items to Trash
  s6: All selected items moved
  s7: Partial result with failures
  [*] --> s0
  [*] --> s1
  s0 --> s2: request approval
  s1 --> s3: show the dry-run plan
  s2 --> s4: you decline or no interactive input is available
  s2 --> s5: you pass --yes or approve in a terminal
  s5 --> s6: report successful and failed items
  s5 --> s7: report successful and failed items
  class s0 blue
  class s1 blue
  class s2 blue
  class s3 teal
  class s4 blue
  class s5 blue
  class s6 teal
  class s7 teal
```

## Install an app from a DMG

[Subsystem skill](../.agents/skills/dmg-install/SKILL.md) · [TLC report](results/dmg-install/report.md) · [SVG](results/dmg-install/chart.svg) · [Source replay evidence](results/dmg-install/evidence.json)

One existing app and one image; mount, find-app, confirmation, removal, copy, cleanup and detach are separate steps. The actual command body runs against fake filesystem and process dependencies. No disk image is mounted; subprocess internals, crash recovery and concurrent installs are excluded. Detach failure is represented but no unconditional successful-detach guarantee is asserted.

![Checked dmg-install flow](results/dmg-install/chart.svg)

```mermaid
---
title: "Install or replace an app from a disk image"
---
stateDiagram-v2
  state "Legend" as legend {
    lg0: Breaks CleanupReportIsTrue or ErrorUnmountsImage or FailedReplacementKeepsOldApp
    lg1: Path to the CleanupReportIsTrue or ErrorUnmountsImage or FailedReplacementKeepsOldApp bug
  }
  class lg0 breaks
  class lg1 bugPath
  s0: You choose a disk image
  s1: Image could not be mounted
  s2: Image mounted read-only
  s3: Waiting for install approval
  s4: Command exits with the image still mounted
  s5: Approved#59; replacing the existing app
  s6: Previous app deleted#59; copying the replacement
  s7: New app copied
  s8: Copy failed#59; previous app lost#59; image mounted
  s9: Install reported#59; preparing to eject
  s10: Reports image removed#59; original image remains mounted
  s11: App installed#59; image ejected
  s12: Reports image removed#59; original image still exists
  s13: Install reported#59; detach failed
  [*] --> s0
  s0 --> s1: mount fails
  s0 --> s2: mount the image
  s2 --> s3: an app is found
  s2 --> s4: the image contains no app
  s3 --> s4: you decline or --yes is missing without a terminal
  s3 --> s5: you approve the installation
  s5 --> s6: delete the old app
  s6 --> s7: copy the replacement
  s6 --> s8: copying the replacement fails
  s7 --> s9: delete the input image or keep the input image
  s7 --> s10: input-image deletion fails silently
  s9 --> s11: normal return ejects the image
  s9 --> s13: eject fails silently
  s10 --> s12: normal return ejects the image
  classDef breaks fill:#ffecee,stroke:#e72e3b,stroke-width:2.5px,color:#cd2834
  class s0 bugPath
  class s2 bugPath
  class s3 bugPath
  class s4 breaks
  class s4 bugPath
  class s5 bugPath
  class s6 bugPath
  class s7 bugPath
  class s8 breaks
  class s8 bugPath
  class s10 breaks
  class s10 bugPath
  class s12 breaks
```

## Open and leave the dashboard

[Subsystem skill](../.agents/skills/terminal-session/SKILL.md) · [TLC report](results/terminal-session/report.md) · [SVG](results/terminal-session/chart.svg) · [Source replay evidence](results/terminal-session/evidence.json)

One terminal session: piped output, saved settings, raw mode, alternate screen, normal quit, handled fatal signal, idempotent cleanup. The complete TUI enum is compiled from source and tested on real pseudo-terminals with q and SIGTERM; all termios fields and the cursor/alternate-screen restore sequence are compared. SIGKILL, startup signals before failsafe registration, resize and Unicode input are excluded.

![Checked terminal-session flow](results/terminal-session/chart.svg)

```mermaid
---
title: "Enter and leave the terminal dashboard"
---
stateDiagram-v2
  s0: You open the dashboard or app switcher
  s1: Your terminal is usable again
  s2: Original terminal settings saved
  s3: Keyboard input in raw mode
  s4: Dashboard visible#59; cursor hidden
  s5: Restoring terminal settings and cursor
  [*] --> s0
  s0 --> s1: output is piped#59; print one frame
  s0 --> s2: save the terminal settings
  s2 --> s3: enable raw keyboard input
  s3 --> s4: enter the alternate screen
  s4 --> s5: a handled fatal signal interrupts the app or you press q, Escape, or keyboard Ctrl-C
  s5 --> s1: restore the saved terminal and cursor
```

## Keep the Mac awake

[Subsystem skill](../.agents/skills/keep-awake/SKILL.md) · [TLC report](results/keep-awake/report.md) · [SVG](results/keep-awake/chart.svg) · [Source replay evidence](results/keep-awake/evidence.json)

One assertion; duration/PID completion and indefinite SIGINT waiting. The actual run body uses fake IOPM calls, real signal dispatch and Thread.sleep; the child is killed after SIGINT fails to complete. No real power assertion is acquired. PID reuse, EPERM, wall-clock jumps and SIGTERM are excluded.

![Checked keep-awake flow](results/keep-awake/chart.svg)

```mermaid
---
title: "Keep the Mac awake until work finishes"
---
stateDiagram-v2
  state "Legend" as legend {
    lg0: Path to the InterruptEventuallyReleases bug
    lg1: Repeats forever, so InterruptEventuallyReleases breaks
  }
  class lg0 bugPath
  class lg1 repeats
  s0: You start keep-awake
  s1: Sleep prevention active until the deadline
  s2: Command finished#59; assertion released
  s3: Sleep prevention active until Ctrl-C
  s4: Sleep prevention active while the PID is alive
  s5: Ctrl-C queued#59; deadline still applies
  s6: Duration ended or watched process disappeared
  s7: Ctrl-C queued#59; indefinite assertion remains active
  s8: Ctrl-C queued#59; watched PID still applies
  [*] --> s0
  s0 --> s1: macOS grants the assertion
  s0 --> s2: macOS rejects the assertion
  s0 --> s3: macOS grants the assertion
  s0 --> s4: macOS grants the assertion
  s1 --> s5: you press Ctrl-C
  s1 --> s6: the requested duration ends
  s3 --> s7: you press Ctrl-C
  s4 --> s8: you press Ctrl-C
  s4 --> s6: the watched PID disappears
  s5 --> s6: the requested duration ends
  s6 --> s2: normal return releases the assertion
  s8 --> s6: the watched PID disappears
  class s0 bugPath
  class s3 bugPath
  class s7 repeats
```

## Refresh agent usage

[Subsystem skill](../.agents/skills/usage-index/SKILL.md) · [TLC report](results/usage-index/report.md) · [SVG](results/usage-index/chart.svg) · [Source replay evidence](results/usage-index/evidence.json)

One file, two usage records, unchanged reuse, a partial-line completion and full reindex. Values 1/2 in the model represent 10/15 in the real source replay. Arithmetic and parsing execute on actual source over scratch JSONL fixtures. Same-size rewrites, cross-process index writes, budget edges, malformed JSON and today-by-mtime semantics are excluded.

![Checked usage-index flow](results/usage-index/chart.svg)

```mermaid
---
title: "Read and refresh local agent usage"
---
stateDiagram-v2
  state "Legend" as legend {
    lg0: Breaks CumulativeUsageIsMaximum
    lg1: Path to the CumulativeUsageIsMaximum bug
  }
  class lg0 breaks
  class lg1 bugPath
  s0: No cached usage for this transcript
  s1: First complete usage record cached
  s2: Appended cumulative usage is counted twice
  s3: Incomplete last line retained for next scan
  s4: Completed line counted once
  s5: Full reindex restores the correct maximum
  [*] --> s0
  s0 --> s1: read the first complete record
  s1 --> s2: tail-parse a new cumulative Codex record
  s1 --> s3: a transcript ends partway through a line
  s2 --> s5: you pass --reindex
  s3 --> s4: the writer completes that line
  classDef breaks fill:#ffecee,stroke:#e72e3b,stroke-width:2.5px,color:#cd2834
  class s0 bugPath
  class s1 bugPath
  class s2 breaks
  class s2 bugPath
```

## Set a fan target

[Subsystem skill](../.agents/skills/fan-control/SKILL.md) · [TLC report](results/fan-control/report.md) · [SVG](results/fan-control/chart.svg) · [Source replay evidence](results/fan-control/evidence.json)

One valid fan, a validated in-range RPM, optional forced-bit support, and accepted/rejected/mismatching firmware responses. Actual Set.run executes against fake SMC dependencies. Physical cooling, SMC encoding, range arithmetic, concurrent commands, fans auto and audio routing are excluded.

![Checked fan-control flow](results/fan-control/chart.svg)

```mermaid
---
title: "Set and verify a fan target"
---
stateDiagram-v2
  state "Legend" as legend {
    lg0: Breaks FailureRestoresAutomatic
    lg1: Path to the FailureRestoresAutomatic bug
  }
  class lg0 breaks
  class lg1 bugPath
  s0: You choose an in-range target
  s1: You approve the hardware write
  s2: Write refused or unsupported
  s3: Forced-bit support unavailable
  s4: Manual mode enabled
  s5: Error reported#59; manual mode remains set
  s6: Target written#59; verifying readback
  s7: Matching target confirmed
  [*] --> s0
  s0 --> s1: you approve
  s0 --> s2: you decline or --yes is missing without a terminal
  s1 --> s3: the forced bit is unsupported
  s1 --> s4: set the manual-control bit
  s3 --> s2: the target cannot be written
  s3 --> s6: the driver accepts the target
  s4 --> s5: the target cannot be written
  s4 --> s6: the driver accepts the target
  s6 --> s7: readback matches within two RPM
  s6 --> s2: firmware reports a different target or readback fails
  s6 --> s5: firmware reports a different target or readback fails
  classDef breaks fill:#ffecee,stroke:#e72e3b,stroke-width:2.5px,color:#cd2834
  class s0 bugPath
  class s1 bugPath
  class s4 bugPath
  class s5 breaks
  class s5 bugPath
```

## Take a camera photo

[Subsystem skill](../.agents/skills/camera-capture/SKILL.md) · [TLC report](results/camera-capture/report.md) · [SVG](results/camera-capture/chart.svg) · [Source replay evidence](results/camera-capture/evidence.json)

One session, one frame, permission denial, frame timeout and encoding/write failure. The replay extracts the actual start/defer/first-frame block; conversion and disk-write failures share the same Out.fail abstraction but are not individually injected. OS cleanup on process exit is outside the explicit-cleanup invariant.

![Checked camera-capture flow](results/camera-capture/chart.svg)

```mermaid
---
title: "Take one camera photo"
---
stateDiagram-v2
  state "Legend" as legend {
    lg0: Breaks ExplicitStopOnError
    lg1: Path to the ExplicitStopOnError bug
  }
  class lg0 breaks
  class lg1 bugPath
  s0: You select a camera and filename
  s1: Permission granted#59; camera configured
  s2: Camera access refused
  s3: Camera running#59; waiting for a frame
  s4: Converting and writing the photo
  s5: Process exits before explicit camera stop
  s6: Photo saved#59; returning from command
  s7: Camera explicitly stopped
  [*] --> s0
  s0 --> s1: camera access is granted
  s0 --> s2: camera access is denied
  s1 --> s3: the camera starts
  s3 --> s4: the first frame arrives
  s3 --> s5: no frame arrives before the timeout
  s4 --> s5: conversion or disk write fails
  s4 --> s6: the photo is written
  s6 --> s7: normal return runs cleanup
  classDef breaks fill:#ffecee,stroke:#e72e3b,stroke-width:2.5px,color:#cd2834
  class s0 bugPath
  class s1 bugPath
  class s3 bugPath
  class s5 breaks
  class s5 bugPath
```
