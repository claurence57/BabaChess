--
--  BabaChess : UCI "info" reporting and the console lock
--
--  Everything the search prints: the per-iteration "info ... pv ..." lines
--  (including MultiPV, one line per reported root move), the console lock
--  shared by the command loop and the search threads, and the worker
--  exception log. Nothing here is on the search's hot path: the report runs
--  once per completed iteration.
--
--  Output is off by default (--selftest and --bench stay silent) and turned
--  on by the "uci" handshake, exactly as before.
--

with Ada.Exceptions;

with BBChess.Eval;
use BBChess.Eval;

package BBChess.Search.Report is

   procedure Set_Enabled (On : in Boolean);
   function Enabled return Boolean;

   procedure Put_Line (S : in String);
   --  One line to standard output, under the package-wide console lock.

   procedure Log_Exception
     (Context    : in String;
      Occurrence : in Ada.Exceptions.Exception_Occurrence);
   --  Report an otherwise-swallowed task exception on standard *error*
   --  (never stdout: the UCI stream must stay clean), under the same lock.

   type Line_Info is record
      Move  : Move_Type  := Empty_Move;
      Score : Score_Type := 0;
   end record;

   type Line_Array is array (Positive range <>) of Line_Info;
   --  The root lines of a MultiPV search, best first. An empty array means
   --  "single line": the PV is then read from the table and reported once.

   Empty_Lines : constant Line_Array (1 .. 0) := (others => <>);

   procedure Iteration (Root      : in Position_Type;
                        Depth     : in Natural;
                        Sel_Depth : in Natural;
                        Score     : in Score_Type;
                        Elapsed   : in Duration;
                        Nodes     : in Node_Count_Type;
                        Tb_Hits   : in Natural;
                        Best      : in Move_Type;
                        Lines     : in Line_Array);
   --  Emit this iteration's "info" line(s). Does nothing while disabled.

end BBChess.Search.Report;
