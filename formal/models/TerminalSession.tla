----------------------------- MODULE TerminalSession -------------------------
CONSTANT Mutation
VARIABLE s
vars == <<s>>
\* termios snapshot precedes raw mode; restore is idempotent.
Init == s = [phase |-> "ready", saved |-> FALSE, raw |-> FALSE,
             alternate |-> FALSE, hidden |-> FALSE]
PipeOutput == /\ s.phase = "ready" /\ s' = [s EXCEPT !.phase = "done"]
SaveTermios == /\ s.phase = "ready"
               /\ s' = [s EXCEPT !.phase = "snapshot", !.saved = ~Mutation]
EnterRaw == /\ s.phase = "snapshot" /\ s' = [s EXCEPT !.phase = "raw", !.raw = TRUE]
ShowDashboard == /\ s.phase = "raw"
                 /\ s' = [s EXCEPT !.phase = "active", !.alternate = TRUE, !.hidden = TRUE]
Quit == /\ s.phase = "active" /\ s' = [s EXCEPT !.phase = "restoring"]
FatalSignal == /\ s.phase = "active" /\ s' = [s EXCEPT !.phase = "restoring"]
Restore == /\ s.phase = "restoring"
           /\ s' = [s EXCEPT !.phase = "done", !.saved = FALSE,
                      !.raw = IF s.saved THEN FALSE ELSE s.raw,
                      !.alternate = IF s.saved THEN FALSE ELSE s.alternate,
                      !.hidden = IF s.saved THEN FALSE ELSE s.hidden]
RestoreAgain == /\ s.phase = "done" /\ UNCHANGED vars
Next == PipeOutput \/ SaveTermios \/ EnterRaw \/ ShowDashboard \/ Quit
        \/ FatalSignal \/ Restore \/ RestoreAgain
Spec == Init /\ [][Next]_vars
TypeOK == /\ s.phase \in {"ready", "snapshot", "raw", "active", "restoring", "done"}
          /\ s.saved \in BOOLEAN /\ s.raw \in BOOLEAN
          /\ s.alternate \in BOOLEAN /\ s.hidden \in BOOLEAN
TerminalRestored == s.phase = "done" => ~s.raw /\ ~s.alternate /\ ~s.hidden
=============================================================================
