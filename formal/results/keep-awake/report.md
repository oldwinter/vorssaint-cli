# KeepAwake

TLC reached 18 states and 25 steps. The chart draws 9 states and 12 arrows.
The chart does not draw 3 steps that stay in one chart state.
The view hides 5 steps, so the chart does not draw them.

## InterruptEventuallyReleases breaks
TLC's counterexample is in tlc-InterruptEventuallyReleases.out. It has 2 steps:
0. You start keep-awake
1. macOS grants the assertion: Sleep prevention active until Ctrl-C
2. you press Ctrl-C: Ctrl-C queued; indefinite assertion remains active
The run stops in "Ctrl-C queued; indefinite assertion remains active" forever.

## Rules that hold
TypeOK, ReleaseOnReturn, NoDeadlock
