-------------------------- MODULE ScreenRecording --------------------------
EXTENDS Naturals
CONSTANT Mutation
VARIABLE s
vars == <<s>>
\* run / stopCapture / finishWriting / stream(didOutputSampleBuffer:).
\* Each callback body is one lock-held step. Stop and finalization are separate.
Init == s = [phase |-> "ready", frames |-> 0, failed |-> FALSE,
             atFailure |-> 0, stopped |-> FALSE, lateAppend |-> FALSE]
Start == /\ s.phase = "ready"
         /\ s' = [s EXCEPT !.phase = "recording"]
PermissionDenied == /\ s.phase = "ready"
                    /\ s' = [s EXCEPT !.phase = "error"]
Frame == /\ s.phase = "recording" /\ s.frames = 0
         /\ (~s.failed \/ Mutation)
         /\ s' = [s EXCEPT !.frames = 1]
StreamError == /\ s.phase = "recording" /\ ~s.failed
               /\ s' = [s EXCEPT !.failed = TRUE, !.atFailure = s.frames]
RequestStop == /\ s.phase = "recording"
               /\ s' = [s EXCEPT !.phase = "stopping"]
StopAcknowledged == /\ s.phase = "stopping"
                    /\ s' = [s EXCEPT !.phase = "drained", !.stopped = TRUE]
StopTimesOut == /\ s.phase = "stopping"
                /\ s' = [s EXCEPT !.phase = "drained"]
FinishWriter == /\ s.phase = "drained"
                /\ s' = [s EXCEPT !.phase = "finalized"]
LateFrame == /\ s.phase = "finalized" /\ s.frames = 1 /\ ~s.stopped /\ ~s.failed
             /\ s' = [s EXCEPT !.phase = "late-frame", !.lateAppend = TRUE]
Publish == /\ s.phase \in {"finalized", "late-frame"}
           /\ s' = [s EXCEPT !.phase = IF s.frames > 0 /\ ~s.failed THEN "saved" ELSE "error"]
Done == /\ s.phase \in {"saved", "error"} /\ UNCHANGED vars
Next == Start \/ PermissionDenied \/ Frame \/ StreamError \/ RequestStop
        \/ StopAcknowledged \/ StopTimesOut \/ FinishWriter \/ LateFrame \/ Publish \/ Done
Spec == Init /\ [][Next]_vars
TypeOK == /\ s.phase \in {"ready", "recording", "stopping", "drained", "finalized",
                          "late-frame", "saved", "error"}
          /\ s.frames \in 0..1 /\ s.atFailure \in 0..1
          /\ s.failed \in BOOLEAN /\ s.stopped \in BOOLEAN /\ s.lateAppend \in BOOLEAN
FailureStopsFrames == s.failed => s.frames = s.atFailure
NoAppendAfterFinish == ~s.lateAppend
=============================================================================
