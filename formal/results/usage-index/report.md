# UsageIndex

TLC reached 6 states and 8 steps. The chart draws 6 states and 5 arrows.
The chart does not draw 1 steps that stay in one chart state.
The view hides 2 steps, so the chart does not draw them.

## CumulativeUsageIsMaximum breaks
The shortest path has 2 steps:
0. No cached usage for this transcript
1. read the first complete record: First complete usage record cached
2. tail-parse a new cumulative Codex record: Appended cumulative usage is counted twice

## Rules that hold
TypeOK, PartialLineRetained, NoDeadlock
