---
name: fan-control
description: "Recheck the fan control state machine when changing its lifecycle, failure handling, or covered source; run bounded TLC verification and source replay."
---

# Fan control

Promise: A successful manual target write must have matching readback within two RPM.

User harm: The manual-control bit can remain set after a later target write or readback fails.

## Run and decide

1. From the repository root, read the `fan-control` entry in `formal/coverage.json` and the covered functions below. Compare the model's step boundaries with the current implementation before trusting a result.
2. Run `python3 formal/check.py --subsystem fan-control --mutations`. The runner pins TLC 1.7.4 by checksum, checks every invariant separately, compiles actual Swift source into isolated replay programs, and checks a matching model mutation. Read the printed scratch directory's `summary.json`, `replay-fan-control/receipt.json`, and TLC logs. Exit 1 means a recorded finding remains; exit 2 means verification is inconclusive. An unexpected pass also requires review.
3. Use `/statechart` for **every** TLA+ result. Load the installed skill for its current invocation. Copy `formal/models/FanControl.tla`, its `.cfg`, and its `.view.mjs` into a fresh scratch directory outside this repository. Read each shortest path in the source's terms; draw the passing graph too. Keep terminal stuttering steps in the model.
4. If a rule fails, replay its action sequence against the covered Swift source with the isolated replay program. If a path does not reproduce, treat the path as a modeling error until evidence resolves it. Preserve actual failures as findings; change product behavior only with user authorization.
5. After an intended implementation change, update the model, replay and scratch mutation together. Rerun the command, review each recorded expectation, then update this skill's synchronization commit and the entry's source hashes. Move the commit forward only after confirming model/source agreement; a hash match alone is not a proof. Use `/maintain-formal-verification-skill` after unverified changes.

## Coverage record

Last source review: 2026-11-11. Synchronization commit: `d91fec94f4641afd646336f1ce128620676c4999`.

- `Sources/vorssaint/Commands/Fans.swift`
- `Sources/vorssaint/Core/Output.swift`

Covered functions and boundaries: `Fans.Set.run`; `Fans.setForcedBit`; `SMC.writeNumber (abstract boundary)`; `Out.confirm`.

Model: `formal/models/FanControl.tla`; configuration and reader-facing view live beside it. Exact source fingerprints, expected findings, and mutation rule live in `formal/coverage.json`.

Bounds and assumptions: One valid fan, a validated in-range RPM, optional forced-bit support, and accepted/rejected/mismatching firmware responses. Actual Set.run executes against fake SMC dependencies. Physical cooling, SMC encoding, range arithmetic, concurrent commands, fans auto and audio routing are excluded.

Recorded findings: `FailureRestoresAutomatic`. The checked paths and their source replay evidence are in `formal/results/` and the runner's scratch receipts.

Negative control: Remove the readback tolerance guard; ignored writes must incorrectly report success. The mutation changes only a scratch copy; the working product source stays intact. The matching model mutation must break `SuccessMatchesReadback`. The handoff is complete only after baseline replays succeed, the scratch regression is detected, and baseline checks return to the same finding set.
