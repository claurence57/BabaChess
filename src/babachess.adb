--
--  BabaChess - main entry point.
--
--  * With "--selftest": run the internal test-suite.
--  * Otherwise: a UCI / XBoard chess engine. The command loop itself lives in
--    BBChess.Protocol (which owns the session state and dispatch); this file
--    keeps the command-line modes, the special benchmark / eval-dump modes and
--    the standard input loop, and supplies the output writer (the shared
--    console lock).
--

with Ada.Text_IO;
with Ada.Command_Line;
with Ada.IO_Exceptions;
with Ada.Real_Time;
with Ada.Strings.Unbounded;

use Ada.Real_Time;

with BBChess.Search;
use BBChess.Search;

with BBChess.Eval;
use BBChess.Eval;

with BBChess.Fen;
use BBChess.Fen;

with BBChess.Board;
use BBChess.Board;

with BBChess.Moves;
use BBChess.Moves;

with BBChess.Self_Tests;

with BBChess.Protocol;

with BBChess.Text;
use BBChess.Text;

procedure BabaChess is

   Input_Line : String (1 .. 8192);
   Last       : Natural;

   -- Fixed set of positions exercising the evaluation and the search. The
   -- benchmark searches every one at a fixed depth and reports the total
   -- node count and nodes/second, so that each optimization can be measured
   -- against the same workload.
   procedure Run_Bench (Depth : in Natural) is
      use Ada.Strings.Unbounded;
      Fens : constant array (Positive range <>) of Unbounded_String :=
        (1 => To_Unbounded_String ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"),
         2 => To_Unbounded_String ("r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"),
         3 => To_Unbounded_String ("rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2"),
         4 => To_Unbounded_String ("r1bq1rk1/pp3ppp/2n1pn2/2pp4/3P1B2/2NBPN2/PPPQ1PPP/2KR3R w - - 0 1"),
         5 => To_Unbounded_String ("r4rk1/pppbqppp/2nbp3/3P4/4B3/5N2/PPP2PPP/R1BQR1K1 b - - 0 11"),
         6 => To_Unbounded_String ("r4r2/pppbnppk/3b4/3p4/8/5N2/PPP2PPP/R1BQ2K1 w - - 0 14"),
         7 => To_Unbounded_String ("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"),
         8 => To_Unbounded_String ("4k3/8/8/8/8/8/4P3/4K3 w - - 0 1"));
      Total_Nodes : Node_Count_Type := 0;
      Pos         : Position_Type;
      T0          : constant Time := Clock;
      Elapsed     : Duration;
      Nps         : Long_Float;
   begin
      Reset_Search;
      Reset_Nodes;
      for I in Fens'Range loop
         Load (Pos, To_String (Fens (I)));
         declare
            M : constant Move_Type := Best_Move (Pos, Depth);
         begin
            null;
            pragma Unreferenced (M);
         end;
      end loop;
      Elapsed := To_Duration (Clock - T0);
      Total_Nodes := Nodes_Searched;

      if Elapsed > 0.0 then
         Nps := Long_Float (Total_Nodes) / Long_Float (Elapsed);
      else
         Nps := 0.0;
      end if;

      Ada.Text_IO.Put_Line
        ("bench depth" & Natural'Image (Depth)
         & ": " & Natural'Image (Fens'Length) & " positions, "
         & Node_Count_Type'Image (Total_Nodes) & " nodes, "
         & Duration'Image (Elapsed) & " s, "
         & Long_Float'Image (Nps / 1000.0) & " knps");
   end Run_Bench;

   -- Read one position per line ("FEN" or "FEN;result") and print the
   -- White-positive static evaluation, one integer per line. Used by the
   -- automatic tuner.
   procedure Run_Eval_Fens (File_Name : in String) is
      F    : Ada.Text_IO.File_Type;
      Line : String (1 .. 512);
      L_Last : Natural;
      Pos  : Position_Type;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, File_Name);
      while not Ada.Text_IO.End_Of_File (F) loop
         Ada.Text_IO.Get_Line (F, Line, L_Last);
         declare
            S    : constant String := Line (1 .. L_Last);
            Semi : Natural := 0;
         begin
            for I in S'Range loop
               if S (I) = ';' then
                  Semi := I;
                  exit;
               end if;
            end loop;
            declare
               Fen : constant String :=
                 (if Semi = 0 then S else S (S'First .. Semi - 1));
            begin
               if Fen'Length > 0 then
                  begin
                     Load (Pos, Fen);
                     Ada.Text_IO.Put_Line (Integer'Image (Static (Pos)));
                  exception
                     when Constraint_Error =>
                        Ada.Text_IO.Put_Line ("0");
                  end;
               end if;
            end;
         end;
      end loop;
      Ada.Text_IO.Close (F);
   end Run_Eval_Fens;

begin
   -- Optional parameter file (evaluation and search parameters; applies to
   -- every mode). The same file may mix "P_*" (eval) and "S_*" (search)
   -- names, so both loaders read it.
   for I in 1 .. Ada.Command_Line.Argument_Count loop
      if Ada.Command_Line.Argument (I) = "--params"
        and then I < Ada.Command_Line.Argument_Count
      then
         Load_Params (Ada.Command_Line.Argument (I + 1));
         Load_Search_Params (Ada.Command_Line.Argument (I + 1));
      end if;
   end loop;

   -- Optional Syzygy tablebase directory (playing modes).
   for I in 1 .. Ada.Command_Line.Argument_Count loop
      if Ada.Command_Line.Argument (I) = "--syzygy"
        and then I < Ada.Command_Line.Argument_Count
      then
         BBChess.Protocol.Configure_Syzygy
           (Ada.Command_Line.Argument (I + 1));
      end if;
   end loop;

   -- Optional number of search threads (Lazy SMP): "--threads N" (separate
   -- argument), "-TN" or "--thread=N" (same argument).
   for I in 1 .. Ada.Command_Line.Argument_Count loop
      declare
         A : constant String := Ada.Command_Line.Argument (I);
         N : constant Natural := Thread_Count (A, 0);
      begin
         if A = "--threads"
           and then I < Ada.Command_Line.Argument_Count
         then
            Set_Threads (Natural'Value (Ada.Command_Line.Argument (I + 1)));
         elsif N /= 0 then
            Set_Threads (N);
         end if;
      exception
         when Constraint_Error =>
            Set_Threads (1);
      end;
   end loop;

   -- Dump the current evaluation and search parameters.
   if Ada.Command_Line.Argument_Count >= 1
     and then Ada.Command_Line.Argument (1) = "--dump-params"
   then
      Dump_Params;
      Dump_Search_Params;
      return;
   end if;

   -- Dump the static evaluation of every FEN of a file (tuning dataset).
   if Ada.Command_Line.Argument_Count >= 2
     and then Ada.Command_Line.Argument (1) = "--eval-fens"
   then
      Run_Eval_Fens (Ada.Command_Line.Argument (2));
      return;
   end if;

   -- Self test mode.
   if Ada.Command_Line.Argument_Count > 0
     and then Ada.Command_Line.Argument (1) = "--selftest"
   then
      BBChess.Self_Tests.Run;
      return;
   end if;

   -- Benchmark mode (optional depth as second argument, default 8).
   if Ada.Command_Line.Argument_Count > 0
     and then Ada.Command_Line.Argument (1) = "--bench"
   then
      declare
         D : Natural := 8;
      begin
         if Ada.Command_Line.Argument_Count >= 2 then
            begin
               D := Natural'Value (Ada.Command_Line.Argument (2));
            exception
               when Constraint_Error => D := 8;
            end;
         end if;
         Run_Bench (D);
      end;
      return;
   end if;

   -- Interactive / protocol mode: hand the command loop to BBChess.Protocol,
   -- which owns the session state and emits every output line through the
   -- console lock installed here (BBChess.Search.Locked_Put_Line). Ada.Text_IO
   -- is not task-safe and the asynchronous UCI search task prints "bestmove"
   -- while the command loop may answer "readyok"; a single shared lock keeps
   -- the two streams from interleaving. The book is loaded unless --book
   -- already did (the special modes returned before this point).
   BBChess.Protocol.Initialize (Locked_Put_Line'Access);

   -- --book is applied here, after the writer is installed, so an unreadable
   -- or malformed book is reported; without --book the conventional locations
   -- are probed silently.
   declare
      Book_Given : Boolean := False;
   begin
      for I in 1 .. Ada.Command_Line.Argument_Count loop
         if Ada.Command_Line.Argument (I) = "--book"
           and then I < Ada.Command_Line.Argument_Count
         then
            BBChess.Protocol.Configure_Book (Ada.Command_Line.Argument (I + 1));
            Book_Given := True;
         end if;
      end loop;
      if not Book_Given then
         BBChess.Protocol.Load_Default_Book;
      end if;
   end;

   Main_Loop : loop
      Ada.Text_IO.Get_Line (Input_Line, Last);
      BBChess.Protocol.Process (Input_Line (1 .. Last));
      exit Main_Loop when BBChess.Protocol.Exit_Requested;
   end loop Main_Loop;

   BBChess.Protocol.Shutdown;
   Ada.Text_IO.Put_Line ("Thanks for playing with BabaChess!");
exception
   -- A clean close of the input (e.g. the GUI quitting) must not abort.
   -- If a UCI search is still running, stop it so the process can exit.
   when Ada.IO_Exceptions.End_Error =>
      BBChess.Protocol.Shutdown;
end BabaChess;
