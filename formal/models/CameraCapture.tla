---------------------------- MODULE CameraCapture ----------------------------
CONSTANT Mutation
VARIABLE s
vars == <<s>>
Init == s = [phase |-> "ready", running |-> FALSE, saved |-> FALSE]
Allow == /\ s.phase = "ready" /\ s' = [s EXCEPT !.phase = "configured"]
Deny == /\ s.phase = "ready" /\ s' = [s EXCEPT !.phase = "error"]
Start == /\ s.phase = "configured"
         /\ s' = [s EXCEPT !.phase = "waiting", !.running = TRUE]
ReceiveFrame == /\ s.phase = "waiting" /\ s' = [s EXCEPT !.phase = "encoding"]
\* Out.fail calls Foundation.exit, which bypasses Swift's defer.
FrameTimeout == /\ s.phase = "waiting" /\ s' = [s EXCEPT !.phase = "error"]
EncodeOrWriteFails == /\ s.phase = "encoding" /\ s' = [s EXCEPT !.phase = "error"]
Save == /\ s.phase = "encoding"
        /\ s' = [s EXCEPT !.phase = "returning", !.saved = TRUE]
ReturnAndDefer == /\ s.phase = "returning"
                  /\ s' = [s EXCEPT !.phase = "done", !.running = Mutation]
Done == /\ s.phase \in {"done", "error"} /\ UNCHANGED vars
Next == Allow \/ Deny \/ Start \/ ReceiveFrame \/ FrameTimeout
        \/ EncodeOrWriteFails \/ Save \/ ReturnAndDefer \/ Done
Spec == Init /\ [][Next]_vars
TypeOK == /\ s.phase \in {"ready", "configured", "waiting", "encoding", "returning", "done", "error"}
          /\ s.running \in BOOLEAN /\ s.saved \in BOOLEAN
StopsOnSuccess == s.phase = "done" => ~s.running
ExplicitStopOnError == s.phase = "error" => ~s.running
=============================================================================
