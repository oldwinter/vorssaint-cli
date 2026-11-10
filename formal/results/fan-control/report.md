# FanControl

TLC reached 12 states and 20 steps. The chart draws 8 states and 11 arrows.
The view hides 6 steps, so the chart does not draw them.

## FailureRestoresAutomatic breaks
The shortest path has 3 steps:
0. You choose an in-range target
1. you approve: You approve the hardware write
2. set the manual-control bit: Manual mode enabled
3. the target cannot be written: Error reported; manual mode remains set

## Rules that hold
TypeOK, SuccessMatchesReadback, NoDeadlock
