------------------------------ MODULE DmgInstall -----------------------------
CONSTANT Mutation
VARIABLE s
vars == <<s>>
\* One existing app and one input image, with explicit syscall boundaries.
Init == s = [phase |-> "ready", mounted |-> FALSE, confirmed |-> FALSE,
             oldApp |-> TRUE, copied |-> FALSE, source |-> TRUE, reportedRemoved |-> FALSE]
AttachFails == /\ s.phase = "ready" /\ s' = [s EXCEPT !.phase = "error"]
Mount == /\ s.phase = "ready" /\ s' = [s EXCEPT !.phase = "mounted", !.mounted = TRUE]
NoApp == /\ s.phase = "mounted" /\ s' = [s EXCEPT !.phase = "error"]
FindApp == /\ s.phase = "mounted" /\ s' = [s EXCEPT !.phase = "confirming"]
Decline == /\ s.phase = "confirming" /\ ~Mutation /\ s' = [s EXCEPT !.phase = "error"]
Confirm == /\ s.phase = "confirming"
           /\ s' = [s EXCEPT !.phase = "replacing", !.confirmed = ~Mutation]
RemoveOld == /\ s.phase = "replacing"
             /\ s' = [s EXCEPT !.phase = "copying", !.oldApp = FALSE]
CopyFails == /\ s.phase = "copying" /\ s' = [s EXCEPT !.phase = "error"]
Copy == /\ s.phase = "copying"
        /\ s' = [s EXCEPT !.phase = "copied", !.copied = TRUE]
KeepImage == /\ s.phase = "copied" /\ s' = [s EXCEPT !.phase = "returning"]
Cleanup == /\ s.phase = "copied"
           /\ s' = [s EXCEPT !.phase = "returning", !.source = FALSE, !.reportedRemoved = TRUE]
CleanupFails == /\ s.phase = "copied"
                /\ s' = [s EXCEPT !.phase = "returning", !.reportedRemoved = TRUE]
\* This path reaches defer. Its detach can itself fail.
Detach == /\ s.phase = "returning"
          /\ s' = [s EXCEPT !.phase = "done", !.mounted = FALSE]
DetachFails == /\ s.phase = "returning" /\ s' = [s EXCEPT !.phase = "done"]
Done == /\ s.phase \in {"error", "done"} /\ UNCHANGED vars
Next == AttachFails \/ Mount \/ NoApp \/ FindApp \/ Decline \/ Confirm \/ RemoveOld
        \/ CopyFails \/ Copy \/ KeepImage \/ Cleanup \/ CleanupFails \/ Detach \/ DetachFails \/ Done
Spec == Init /\ [][Next]_vars
TypeOK == /\ s.phase \in {"ready", "mounted", "confirming", "replacing", "copying",
                          "copied", "returning", "done", "error"}
          /\ s.mounted \in BOOLEAN /\ s.oldApp \in BOOLEAN /\ s.copied \in BOOLEAN
          /\ s.confirmed \in BOOLEAN /\ s.source \in BOOLEAN /\ s.reportedRemoved \in BOOLEAN
ConfirmedReplacement == ~s.oldApp => s.confirmed
ErrorUnmountsImage == s.phase = "error" => ~s.mounted
FailedReplacementKeepsOldApp == (s.phase = "error" /\ ~s.copied) => s.oldApp
CleanupReportIsTrue == s.reportedRemoved => ~s.source
=============================================================================
