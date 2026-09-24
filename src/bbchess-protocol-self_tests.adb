--
--  BabaChess : protocol layer self tests (body)
--

with Ada.Text_IO;
with Ada.Strings.Unbounded;
use Ada.Strings.Unbounded;

with BBChess.Protocol.UCI;
with BBChess.Protocol.XBoard;

with BBChess.Search;
use BBChess.Search;

with BBChess.Pieces;
use BBChess.Pieces;

with BBChess.Board;
use BBChess.Board;

package body BBChess.Protocol.Self_Tests is

   procedure Assert (Condition : in Boolean; Message : in String) is
   begin
      if not Condition then
         Ada.Text_IO.Put_Line ("FAILED: " & Message);
         raise Program_Error with Message;
      end if;
   end Assert;

   ---------------------------------
   --  Capturing output writer    --
   ---------------------------------

   Max_Lines : constant := 64;
   Lines     : array (1 .. Max_Lines) of Unbounded_String;
   N_Lines   : Natural := 0;

   procedure Capture (S : in String) is
   begin
      if N_Lines < Max_Lines then
         N_Lines := N_Lines + 1;
         Lines (N_Lines) := To_Unbounded_String (S);
      end if;
   end Capture;

   procedure Reset_Capture is
   begin
      N_Lines := 0;
   end Reset_Capture;

   function Captured (N : Positive) return String is
   begin
      if N <= N_Lines then
         return To_String (Lines (N));
      end if;
      return "";
   end Captured;

   ---------------------------------
   --  Pure parser tests          --
   ---------------------------------

   procedure Test_Parse_Go is
      G : BBChess.Protocol.UCI.Go_Params;
   begin
      -- Full parameter list, White side clocks present.
      G := BBChess.Protocol.UCI.Parse_Go
        ("wtime 5000 btime 6000 winc 100 binc 200 movestogo 30 depth 12 nodes 9000 infinite");
      Assert (G.Wtime = 5.0, "go: wtime 5000 ms = 5 s");
      Assert (G.Btime = 6.0, "go: btime 6000 ms = 6 s");
      Assert (G.Winc = 0.1, "go: winc 100 ms = 0.1 s");
      Assert (G.Binc = 0.2, "go: binc 200 ms = 0.2 s");
      Assert (G.Movestogo = 30, "go: movestogo 30");
      Assert (G.Has_Depth and then G.Depth = 12, "go: depth 12");
      Assert (G.Nodes = 9000, "go: nodes 9000");
      Assert (G.Infinite, "go: infinite flag");

      -- movetime selects the fixed budget.
      G := BBChess.Protocol.UCI.Parse_Go ("movetime 250");
      Assert (G.Has_Movetime and then G.Movetime = 0.25,
              "go: movetime 250 ms = 0.25 s");

      -- Empty list: defaults.
      G := BBChess.Protocol.UCI.Parse_Go ("");
      Assert (G.Wtime = 0.0 and then not G.Has_Depth and then G.Depth = 64
              and then not G.Has_Movetime and then G.Movetime = 1.0
              and then G.Nodes = 0 and then not G.Infinite,
              "go: empty parameter list keeps the defaults");

      -- Malformed numbers fall back to the defaults (never raise).
      G := BBChess.Protocol.UCI.Parse_Go ("wtime abc depth xyz nodes q infinite");
      Assert (G.Wtime = 0.0, "go: malformed wtime -> 0");
      Assert (G.Has_Depth and then G.Depth = 64, "go: malformed depth -> 64");
      Assert (G.Nodes = 0, "go: malformed nodes -> 0");
      Assert (G.Infinite, "go: malformed value does not hide a later flag");

      -- Unknown keywords are ignored.
      G := BBChess.Protocol.UCI.Parse_Go ("ponder wtime 1000");
      Assert (G.Wtime = 1.0, "go: unknown keyword ignored");
   end Test_Parse_Go;

   procedure Test_Parse_Setoption is
      S : BBChess.Protocol.UCI.Setoption_Params;
   begin
      S := BBChess.Protocol.UCI.Parse_Setoption
        ("name Threads value 4");
      Assert (To_String (S.Name) = "threads", "setoption: name lower-cased");
      Assert (S.Is_Value, "setoption: 'value' detected");
      Assert (To_String (S.Value) = "4", "setoption: value 4");

      -- Case-insensitivity and a spaced path value.
      S := BBChess.Protocol.UCI.Parse_Setoption
        ("name SyzygyPath VALUE /a/b c/d");
      Assert (To_String (S.Name) = "syzygypath", "setoption: name lower-cased");
      Assert (S.Is_Value, "setoption: VALUE detected case-insensitively");
      Assert (To_String (S.Value) = "/a/b c/d",
              "setoption: spaced value kept whole");

      -- "clear hash" form.
      S := BBChess.Protocol.UCI.Parse_Setoption ("name Clear Hash");
      Assert (To_String (S.Name) = "clear"
              and then To_String (S.Token3) = "hash",
              "setoption: clear hash form");

      -- Missing value: nothing past the name.
      S := BBChess.Protocol.UCI.Parse_Setoption ("name OwnBook");
      Assert (To_String (S.Name) = "ownbook" and then not S.Is_Value,
              "setoption: no value");
   end Test_Parse_Setoption;

   procedure Test_Parse_Level is
      L : BBChess.Protocol.XBoard.Level_Params;
   begin
      L := BBChess.Protocol.XBoard.Parse_Level ("40 5 1");
      Assert (L.Moves_Per_Session = 40, "level: mps 40");
      Assert (L.Base_Seconds = 300.0, "level: 5 minutes = 300 s");
      Assert (L.Increment_Seconds = 1.0, "level: inc 1 s");
      Assert (not L.Base_Has_Colon, "level: whole-minute base");

      -- "MM:SS" base: the clock is deferred to a later "time" command.
      L := BBChess.Protocol.XBoard.Parse_Level ("0 1:30 0");
      Assert (L.Base_Has_Colon, "level: MM:SS base detected");
      Assert (L.Base_Seconds = 0.0, "level: MM:SS leaves the clock to 'time'");

      -- Malformed numeric fields collapse to 0.
      L := BBChess.Protocol.XBoard.Parse_Level ("x y z");
      Assert (L.Moves_Per_Session = 0 and then L.Base_Seconds = 0.0
              and then L.Increment_Seconds = 0.0,
              "level: malformed fields -> 0");

      Assert (BBChess.Protocol.XBoard.Parse_Centiseconds ("250") = 2.5,
              "time: 250 centiseconds = 2.5 s");
      Assert (BBChess.Protocol.XBoard.Parse_Centiseconds ("junk") = 0.0,
              "time: malformed -> 0");
   end Test_Parse_Level;

   ---------------------------------
   --  Dispatch (captured) tests  --
   ---------------------------------

   procedure Test_Dispatch is
   begin
      -- UCI handshake: exact line set.
      Reset_Capture;
      BBChess.Protocol.Initialize (Capture'Access);
      BBChess.Protocol.Process ("uci");
      Assert (N_Lines = 8, "uci handshake emits 8 lines");
      Assert (Captured (1) = "id name BabaChess 1.0", "uci: id name");
      Assert (Captured (8) = "uciok", "uci: final uciok");
      Assert (BBChess.Protocol.Is_UCI, "uci: mode flag set");

      -- isready answers readyok.
      Reset_Capture;
      BBChess.Protocol.Process ("isready");
      Assert (N_Lines = 1 and then Captured (1) = "readyok", "isready -> readyok");

      -- position startpos + moves applies the moves (White knight moved).
      Reset_Capture;
      BBChess.Protocol.Process ("position startpos moves e2e4 e7e5");
      declare
         P : constant Position_Type := BBChess.Protocol.Position_Of;
      begin
         Assert (P.Side = White, "position: Black played, White to move");
         Assert ((P.Pieces (White_Pawn) and Bit (28)) /= 0, "position: e4 pawn");
         Assert ((P.Pieces (Black_Pawn) and Bit (36)) /= 0, "position: e5 pawn");
         Assert (BBChess.Protocol.Key_Of = BBChess.Protocol.Key_Of,
                 "position: key readable");
      end;

      -- An unknown move stops the scan and reports it.
      Reset_Capture;
      BBChess.Protocol.Process ("position startpos moves e2e4 e7e9");
      Assert (N_Lines = 1
              and then Captured (1) = "info string unknown move e7e9",
              "position: unknown move reported");
      declare
         P : constant Position_Type := BBChess.Protocol.Position_Of;
      begin
         Assert (P.Side = Black, "position: e2e4 applied, e7e9 not");
      end;

      -- A bad FEN is rejected, the position is left untouched.
      Reset_Capture;
      BBChess.Protocol.Process ("position fen not-a-fen");
      Assert (N_Lines = 1 and then Captured (1) = "info string bad FEN",
              "position: bad FEN reported");

      -- setoption Threads is accepted without output.
      Reset_Capture;
      BBChess.Protocol.Process ("setoption name Threads value 3");
      Assert (N_Lines = 0, "setoption threads: no output");

      -- XBoard protover: exact feature set.
      Reset_Capture;
      BBChess.Protocol.Process ("xboard");
      BBChess.Protocol.Process ("protover 2");
      Assert (N_Lines = 6, "protover emits 6 lines");
      Assert (Captured (1) = "feature myname=""BabaChess 1.0""", "protover: myname");
      Assert (Captured (6) = "feature done=1", "protover: done");

      -- ping echoes its argument.
      Reset_Capture;
      BBChess.Protocol.Process ("ping 42");
      Assert (N_Lines = 1 and then Captured (1) = "pong 42", "ping -> pong 42");

      Reset_Capture;
      BBChess.Protocol.Process ("ping");
      Assert (N_Lines = 1 and then Captured (1) = "pong", "ping -> pong");

      -- Blank and unknown lines produce no output and do not raise.
      Reset_Capture;
      BBChess.Protocol.Process ("");
      BBChess.Protocol.Process ("   ");
      Assert (N_Lines = 0, "blank line: no output");

      -- "quit" requests the exit without output.
      Reset_Capture;
      BBChess.Protocol.Process ("quit");
      Assert (BBChess.Protocol.Exit_Requested, "quit: exit requested");
      Assert (N_Lines = 0, "quit: no output");

      -- A bare coordinate move is applied (console / cutechess fallback).
      Reset_Capture;
      BBChess.Protocol.Reset;
      BBChess.Protocol.Process ("e2e4");
      declare
         P : constant Position_Type := BBChess.Protocol.Position_Of;
      begin
         Assert ((P.Pieces (White_Pawn) and Bit (28)) /= 0,
                 "bare move: e2e4 applied");
      end;

      -- Leave the console writer installed and the session clean so the rest
      -- of the self test is unaffected.
      Reset_Capture;
      BBChess.Protocol.Reset;
      BBChess.Protocol.Initialize (null);
   end Test_Dispatch;

   ---------
   -- Run --
   ---------

   procedure Run is
   begin
      Test_Parse_Go;
      Test_Parse_Setoption;
      Test_Parse_Level;
      Test_Dispatch;
      Ada.Text_IO.Put_Line ("protocol tests OK");
   end Run;

end BBChess.Protocol.Self_Tests;
