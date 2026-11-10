------------------------------ MODULE FanControl -----------------------------
CONSTANT Mutation
VARIABLE s
vars == <<s>>
\* One valid fan and an in-range RPM. Firmware may reject or ignore writes.
Init == s = [phase |-> "ready", forced |-> FALSE, accepted |-> FALSE,
             matches |-> FALSE, success |-> FALSE]
Decline == /\ s.phase = "ready" /\ s' = [s EXCEPT !.phase = "error"]
Confirm == /\ s.phase = "ready" /\ s' = [s EXCEPT !.phase = "confirmed"]
ForceMode == /\ s.phase = "confirmed"
             /\ s' = [s EXCEPT !.phase = "forced", !.forced = TRUE]
ForcedBitAbsent == /\ s.phase = "confirmed" /\ s' = [s EXCEPT !.phase = "forced"]
WriteFails == /\ s.phase = "forced" /\ s' = [s EXCEPT !.phase = "error"]
WriteAccepted == /\ s.phase = "forced"
                 /\ s' = [s EXCEPT !.phase = "readback", !.accepted = TRUE]
ReadMatches == /\ s.phase = "readback"
               /\ s' = [s EXCEPT !.phase = "done", !.matches = TRUE, !.success = TRUE]
ReadMissing == /\ s.phase = "readback" /\ s' = [s EXCEPT !.phase = "error"]
ReadMismatch == /\ s.phase = "readback"
                /\ s' = [s EXCEPT !.phase = IF Mutation THEN "done" ELSE "error",
                                  !.success = Mutation]
Done == /\ s.phase \in {"error", "done"} /\ UNCHANGED vars
Next == Decline \/ Confirm \/ ForceMode \/ ForcedBitAbsent \/ WriteFails
        \/ WriteAccepted \/ ReadMatches \/ ReadMissing \/ ReadMismatch \/ Done
Spec == Init /\ [][Next]_vars
TypeOK == /\ s.phase \in {"ready", "confirmed", "forced", "readback", "error", "done"}
          /\ s.forced \in BOOLEAN /\ s.accepted \in BOOLEAN
          /\ s.matches \in BOOLEAN /\ s.success \in BOOLEAN
SuccessMatchesReadback == s.success => s.accepted /\ s.matches
FailureRestoresAutomatic == s.phase = "error" => ~s.forced
=============================================================================
