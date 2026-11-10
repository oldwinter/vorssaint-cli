# Formal verification

Run from the repository root:

```sh
python3 formal/check.py
python3 formal/check.py --subsystem usage-index --mutations
```

Each subsystem has a project skill under `.agents/skills/`. The manifest records
the exact source hashes and synchronization commit. After a source change, the
runner refuses to continue until an agent reviews the model and updates that
record. A hash match establishes provenance, not equivalence.

The checks combine finite TLA+ models with executable replays extracted from Swift
source. Replays replace hardware and destructive dependencies with deterministic
fakes. The terminal replay uses a real pseudo-terminal. No check records the
screen, activates a camera, writes hardware, mounts an image, or modifies user data.
Scratch source changes and compiler products live outside the repository.
Replay fixtures compile the extracted bodies in Swift 5 language mode.
The application itself builds and passes its existing tests in Swift 6 mode.
The replays do not establish Swift concurrency or framework correctness.

TLC 1.7.4 is pinned by SHA-256 and cached outside the repository. Java 11+,
Python 3.10+, and the macOS Swift toolchain are required. `TLA2TOOLS` and `JAVA`
can select an existing installation; the jar checksum is still verified.
With mise, install the recorded Java runtime with
`mise install java@temurin-25.0.5+8.0.LTS`. Activation is unnecessary.

Exit codes: **0** all selected rules hold; **1** a recorded violation remains;
**2** infrastructure, source drift, unexpected checker results, or failed replay.
Known findings stay failing checks. `--mutations` additionally proves that each
subsystem's replay detects a scratch regression in its covered Swift source.

For every TLC result, use `/statechart` to read the shortest violation paths or
draw the passing state graph. Load that skill at run time for its current command.
Its implementation paths and options are intentionally absent from these skills
and scripts. Copy the specification, configuration, and view to a fresh scratch
folder before drawing.

`models/` contains the reviewed specifications and reader-facing views.
`results/` contains the checked reports and rendered flow charts from the recorded
run, including the reviewed logs and replay evidence. New logs and replay receipts
go into the printed scratch directory.
Use `/maintain-formal-verification-skill` after code changes that bypassed these
checks.

These are bounded models, not proofs of all Swift executions or Apple's APIs.
The inventory and exact exclusions are in `coverage.json`.
