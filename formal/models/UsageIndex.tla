------------------------------- MODULE UsageIndex ----------------------------
EXTENDS Naturals
CONSTANT Mutation
VARIABLE s
vars == <<s>>
\* Two complete records (10 then 15 in the executable replay).
\* Values 1 and 2 preserve the additive-vs-cumulative distinction.
Init == s = [phase |-> "empty", tokens |-> 0, expected |-> 0,
             partialSafe |-> TRUE]
ReadFirst == /\ s.phase = "empty"
             /\ s' = [s EXCEPT !.phase = "cached", !.tokens = 1, !.expected = 1]
ReuseUnchanged == /\ s.phase = "cached" /\ UNCHANGED vars
\* scanFile adds codexTokens(tail) to the cached maximum.
AppendCumulative == /\ s.phase = "cached"
                    /\ s' = [s EXCEPT !.phase = "appended", !.tokens = 3, !.expected = 2]
PartialLine == /\ s.phase = "cached"
               /\ s' = [s EXCEPT !.phase = "partial"]
CompletePartial == /\ s.phase = "partial"
                   /\ s' = [s EXCEPT !.phase = "completed", !.partialSafe = ~Mutation]
Reindex == /\ s.phase = "appended"
           /\ s' = [s EXCEPT !.phase = "rescanned", !.tokens = 2]
Done == /\ s.phase \in {"completed", "rescanned"} /\ UNCHANGED vars
Next == ReadFirst \/ ReuseUnchanged \/ AppendCumulative \/ PartialLine
        \/ CompletePartial \/ Reindex \/ Done
Spec == Init /\ [][Next]_vars
TypeOK == /\ s.phase \in {"empty", "cached", "appended", "partial", "completed", "rescanned"}
          /\ s.tokens \in 0..3 /\ s.expected \in 0..2 /\ s.partialSafe \in BOOLEAN
PartialLineRetained == s.partialSafe
CumulativeUsageIsMaximum == s.tokens = s.expected
=============================================================================
