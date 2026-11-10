# ScreenRecording

TLC reached 35 states and 44 steps. The chart draws 11 states and 15 arrows.
The chart does not draw 1 steps that stay in one chart state.
The view hides 9 steps, so the chart does not draw them.

## NoAppendAfterFinish breaks
The shortest path has 6 steps:
0. You choose a display and output
1. permission granted; capture starts: Waiting for the first frame
2. a frame arrives: Recording frames
3. duration ends or you press Ctrl-C: Stopping capture
4. stop waits ten seconds and times out: Stop timed out; capture may still be live
5. the video writer finalizes: Writer finalized
6. an unacknowledged callback arrives [after a captured frame]: A late frame reaches the finished writer

## Rules that hold
TypeOK, FailureStopsFrames, NoDeadlock
