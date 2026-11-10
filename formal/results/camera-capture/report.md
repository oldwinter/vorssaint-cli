# CameraCapture

TLC reached 8 states and 11 steps. The chart draws 8 states and 8 arrows.
The view hides 3 steps, so the chart does not draw them.

## ExplicitStopOnError breaks
The shortest path has 3 steps:
0. You select a camera and filename
1. camera access is granted: Permission granted; camera configured
2. the camera starts: Camera running; waiting for a frame
3. no frame arrives before the timeout: Process exits before explicit camera stop

## Rules that hold
TypeOK, StopsOnSuccess, NoDeadlock
