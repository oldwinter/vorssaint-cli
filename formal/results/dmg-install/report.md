# DmgInstall

TLC reached 18 states and 27 steps. The chart draws 14 states and 14 arrows.
The chart does not draw 1 steps that stay in one chart state.
The view hides 9 steps, so the chart does not draw them.

## ErrorUnmountsImage breaks
The shortest path has 2 steps:
0. You choose a disk image
1. mount the image: Image mounted read-only
2. the image contains no app: Command exits with the image still mounted

## FailedReplacementKeepsOldApp breaks
The shortest path has 5 steps:
0. You choose a disk image
1. mount the image: Image mounted read-only
2. an app is found: Waiting for install approval
3. you approve the installation: Approved; replacing the existing app
4. delete the old app: Previous app deleted; copying the replacement
5. copying the replacement fails: Copy failed; previous app lost; image mounted

## CleanupReportIsTrue breaks
The shortest path has 6 steps:
0. You choose a disk image
1. mount the image: Image mounted read-only
2. an app is found: Waiting for install approval
3. you approve the installation: Approved; replacing the existing app
4. delete the old app: Previous app deleted; copying the replacement
5. copy the replacement: New app copied
6. input-image deletion fails silently: Reports image removed; original image remains mounted

## Rules that hold
TypeOK, ConfirmedReplacement, NoDeadlock
