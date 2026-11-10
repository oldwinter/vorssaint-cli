------------------------------- MODULE KeepAwake -----------------------------
CONSTANT Mutation
VARIABLE s
vars == <<s>>
\* The synchronous main-thread loop sleeps; it does not run the main run loop.
Init == \E mode \in {"duration", "pid", "forever"}:
        s = [phase |-> "ready", held |-> FALSE, interrupt |-> FALSE, mode |-> mode]
AcquireFails == /\ s.phase = "ready" /\ s' = [s EXCEPT !.phase = "done"]
Acquire == /\ s.phase = "ready"
           /\ s' = [s EXCEPT !.phase = "awake", !.held = TRUE]
DurationExpires == /\ s.phase \in {"awake", "interrupt-pending"} /\ s.mode = "duration"
                   /\ s' = [s EXCEPT !.phase = "returning"]
WatchedPIDExits == /\ s.phase \in {"awake", "interrupt-pending"} /\ s.mode = "pid"
                   /\ s' = [s EXCEPT !.phase = "returning"]
PressCtrlC == /\ s.phase = "awake" /\ ~s.interrupt
              /\ s' = [s EXCEPT !.interrupt = TRUE, !.phase = "interrupt-pending"]
\* No main-queue callback action: Thread.sleep does not dispatch it.
SleepAgain == /\ s.phase = "interrupt-pending" /\ UNCHANGED vars
ReturnAndRelease == /\ s.phase = "returning"
                    /\ s' = [s EXCEPT !.phase = "done", !.held = Mutation]
Done == /\ s.phase = "done" /\ UNCHANGED vars
Next == AcquireFails \/ Acquire \/ DurationExpires \/ WatchedPIDExits
        \/ PressCtrlC \/ SleepAgain \/ ReturnAndRelease \/ Done
Spec == Init /\ [][Next]_vars /\ WF_vars(ReturnAndRelease)
        /\ WF_vars(DurationExpires) /\ WF_vars(WatchedPIDExits)
TypeOK == /\ s.phase \in {"ready", "awake", "returning", "interrupt-pending", "done"}
          /\ s.held \in BOOLEAN /\ s.interrupt \in BOOLEAN
          /\ s.mode \in {"duration", "pid", "forever"}
ReleaseOnReturn == s.phase = "done" => ~s.held
InterruptEventuallyReleases == s.interrupt ~> ~s.held
=============================================================================
