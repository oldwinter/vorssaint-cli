---------------------------- MODULE FileOperations ---------------------------
EXTENDS Naturals, FiniteSets
CONSTANT Mutation
VARIABLE s
vars == <<s>>
\* Two planned items; each move either succeeds or fails, independently.
Init == \E dry \in BOOLEAN:
        s = [phase |-> "planned", dry |-> dry, asked |-> FALSE, authorized |-> FALSE,
             pending |-> {1, 2}, moved |-> {}, failed |-> {}]
Preview == /\ s.phase = "planned" /\ s.dry /\ ~Mutation
           /\ s' = [s EXCEPT !.phase = "preview"]
Ask == /\ s.phase = "planned" /\ (~s.dry \/ Mutation)
       /\ s' = [s EXCEPT !.phase = "confirming", !.asked = TRUE]
Confirm == /\ s.phase = "confirming"
           /\ s' = [s EXCEPT !.phase = "applying", !.authorized = TRUE]
DeclineOrNoTTY == /\ s.phase = "confirming" /\ s' = [s EXCEPT !.phase = "aborted"]
Move == \E i \in s.pending:
        /\ s.phase = "applying"
        /\ s' = [s EXCEPT !.pending = @ \ {i}, !.moved = @ \cup {i}]
MoveFails == \E i \in s.pending:
             /\ s.phase = "applying"
             /\ s' = [s EXCEPT !.pending = @ \ {i}, !.failed = @ \cup {i}]
Report == /\ s.phase = "applying" /\ s.pending = {}
          /\ s' = [s EXCEPT !.phase = "reported"]
Done == /\ s.phase \in {"preview", "aborted", "reported"} /\ UNCHANGED vars
Next == Preview \/ Ask \/ Confirm \/ DeclineOrNoTTY \/ Move \/ MoveFails \/ Report \/ Done
Spec == Init /\ [][Next]_vars
TypeOK == /\ s.phase \in {"planned", "preview", "confirming", "applying", "aborted", "reported"}
          /\ s.pending \subseteq {1, 2} /\ s.moved \subseteq {1, 2}
          /\ s.failed \subseteq {1, 2} /\ s.dry \in BOOLEAN
          /\ s.asked \in BOOLEAN /\ s.authorized \in BOOLEAN
AuthorizedWrites == s.moved # {} => s.authorized
DryRunBypassesConfirmation == s.dry => ~s.asked
AccountedOnce == /\ s.pending \cup s.moved \cup s.failed = {1, 2}
                 /\ s.pending \cap s.moved = {}
                 /\ s.pending \cap s.failed = {}
                 /\ s.moved \cap s.failed = {}
=============================================================================
