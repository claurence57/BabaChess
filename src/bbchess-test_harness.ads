--
--  BabaChess : minimal test harness
--
--  A tiny pass/fail counter shared by the self tests. A failing check is
--  recorded and printed but does not abort the run, so the first failure no
--  longer masks every later one; the caller reports the final tally and turns
--  a non-zero failure count into a non-zero exit status.
--

package BBChess.Test_Harness is

   procedure Reset;
   --  Zero the counters (start of a run).

   procedure Check (Condition : in Boolean; Message : in String);
   --  Record one check. A False Condition increments the failure count and
   --  prints "FAILED: <Message>"; True increments the pass count.

   function Passed return Natural;
   function Failed return Natural;

end BBChess.Test_Harness;
