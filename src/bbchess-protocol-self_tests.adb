--
--  BabaChess : protocol layer self tests (body)
--

with Ada.Text_IO;
with Ada.Strings.Unbounded;
use Ada.Strings.Unbounded;

with Interfaces;

with BBChess.Hash;
with BBChess.Syzygy;
with BBChess.Protocol.UCI;

with BBChess.Text;
use BBChess.Text;

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

      -- searchmoves: the move tokens, up to the next keyword.
      G := BBChess.Protocol.UCI.Parse_Go
        ("searchmoves e2e4 d2d4 btime 6000 depth 8");
      Assert (G.Has_Searchmoves, "go: searchmoves flag");
      Assert (To_String (G.Searchmoves) = "e2e4 d2d4",
              "go: searchmoves tokens stop at the next keyword");
      Assert (G.Btime = 6.0 and then G.Has_Depth and then G.Depth = 8,
              "go: keywords after searchmoves still parsed");

      -- searchmoves last on the line.
      G := BBChess.Protocol.UCI.Parse_Go ("go depth 5 searchmoves g1f3");
      Assert (To_String (G.Searchmoves) = "g1f3",
              "go: searchmoves at end of line");

      -- perft mode.
      G := BBChess.Protocol.UCI.Parse_Go ("perft 4");
      Assert (G.Has_Perft and then G.Perft_Depth = 4, "go: perft 4");

      -- mate mode, and "mate" terminates a searchmoves list.
      G := BBChess.Protocol.UCI.Parse_Go ("mate 2");
      Assert (G.Has_Mate and then G.Mate_Moves = 2, "go: mate 2");

      G := BBChess.Protocol.UCI.Parse_Go ("searchmoves e2e4 mate 3");
      Assert (To_String (G.Searchmoves) = "e2e4"
              and then G.Has_Mate and then G.Mate_Moves = 3,
              "go: searchmoves stops at the mate keyword");
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
      Assert (To_String (S.Name) = "clear hash"
              and then not S.Is_Value,
              "setoption: clear hash form");

      -- Multi-word name followed by a value: the name is "move overhead",
      -- not just its first word (the historical parser stopped at token 3
      -- and made every multi-word option unreachable).
      S := BBChess.Protocol.UCI.Parse_Setoption
             ("name Move Overhead value 250");
      Assert (To_String (S.Name) = "move overhead"
              and then S.Is_Value
              and then To_String (S.Value) = "250",
              "setoption: multi-word name with value");

      -- Missing value: nothing past the name.
      S := BBChess.Protocol.UCI.Parse_Setoption ("name OwnBook");
      Assert (To_String (S.Name) = "ownbook" and then not S.Is_Value,
              "setoption: no value");
   end Test_Parse_Setoption;

   ---------------------------------
   --  Dispatch (captured) tests  --
   ---------------------------------

   procedure Test_Dispatch is
      --  Same layout as the "eval" rows, so an assertion cannot drift with an
      --  off-by-one in the padding.
      function Row (Label : in String; Value : in String) return String is
        (Label & (1 .. Natural'Max (0, 22 - Label'Length) => ' ') & Value);
   begin
      -- UCI handshake: exact line set.
      Reset_Capture;
      BBChess.Protocol.Initialize (Capture'Access);
      BBChess.Protocol.Process ("uci");
      Assert (N_Lines = 15, "uci handshake emits 15 lines");
      Assert (Captured (1) = "id name BabaChess " & BabaChess_Version,
              "uci: id name");
      Assert (Captured (4) = "option name Clear Hash type button",
              "uci: Clear Hash advertised");
      Assert (Captured (10) = "option name Syzygy50MoveRule type check default true",
              "uci: Syzygy50MoveRule advertised");
      Assert (Captured (11) = "option name Contempt type spin default 0 min -100 max 100",
              "uci: Contempt advertised");
      Assert (Captured (12) = "option name MultiPV type spin default 1 min 1 max 8",
              "uci: MultiPV advertised");
      Assert (Captured (13) = "option name UCI_LimitStrength type check default false",
              "uci: UCI_LimitStrength advertised");
      Assert (Captured (14) = "option name UCI_Elo type spin default 2800 min 1200 max 2800",
              "uci: UCI_Elo advertised with its clamp");
      Assert (Captured (15) = "uciok", "uci: final uciok");
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

      -- The new options are accepted silently too (their advertised ranges
      -- are policed by the handlers, see UCI_Elo below).
      Reset_Capture;
      BBChess.Protocol.Process ("setoption name MultiPV value 3");
      BBChess.Protocol.Process ("setoption name UCI_LimitStrength value true");
      BBChess.Protocol.Process ("setoption name UCI_Elo value 1500");
      Assert (N_Lines = 0, "setoption multipv / limit strength / Elo: no output");

      Reset_Capture;
      BBChess.Protocol.Process ("setoption name Syzygy50MoveRule value false");
      BBChess.Protocol.Process ("setoption name Contempt value -25");
      Assert (N_Lines = 0, "setoption syzygy50moverule / contempt: no output");
      Assert (not BBChess.Syzygy.Fifty_Move_Rule,
              "setoption: Syzygy50MoveRule false is applied");

      -- "d": 22 lines (diagram, FEN, side, castling, Zobrist key).
      Reset_Capture;
      BBChess.Protocol.Process ("position startpos");
      BBChess.Protocol.Process ("d");
      Assert (N_Lines = 22, "d: 22 lines (diagram, FEN, side, castling, key)");
      Assert (Captured (19) = "Fen: rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"
              & " w KQkq - 0 1", "d: startpos FEN");
      Assert (Captured (20) = "White to move", "d: side to move");
      Assert (Captured (21) = "Castling: KQkq", "d: castling rights");
      Assert (Captured (22) = "Key: " & BBChess.Text.Hex_Image
                (Interfaces.Unsigned_64 (BBChess.Hash.Compute
                   (BBChess.Protocol.Position_Of))),
              "d: Zobrist key in hexadecimal");

      -- "eval": per-term breakdown, total and side-to-move score.
      Reset_Capture;
      BBChess.Protocol.Process ("position startpos");
      BBChess.Protocol.Process ("eval");
      Assert (N_Lines = 14, "eval: 14 lines (header, 12 terms, Evaluate)");
      Assert (Captured (1) = "Static: +0 (White's point of view, phase 100/100)",
              "eval: start position is balanced");
      Assert (Captured (10) = Row ("  king safety", "+0"),
              "eval: the king safety row");
      Assert (Captured (12) = Row ("  drawish scaling", "+0"),
              "eval: the drawish scaling row");
      Assert (Captured (14) = "Evaluate: +10 (side to move, tempo +10)",
              "eval: tempo is reported");

      -- "go perft N": per-move counts then the total, and no bestmove.
      Reset_Capture;
      BBChess.Protocol.Process ("position startpos");
      BBChess.Protocol.Process ("go perft 2");
      Assert (Captured (1) = "info string a2a3 20",
              "perft: first root move and its count");
      Assert (Captured (N_Lines) = "info string perft 2 400",
              "perft 2 from the start position = 400");

      --  XBoard commands are gone: they must be ignored, without output and
      --  without touching the position.
      Reset_Capture;
      declare
         P_Before : constant Position_Type := BBChess.Protocol.Position_Of;
      begin
         BBChess.Protocol.Process ("xboard");
         BBChess.Protocol.Process ("protover 2");
         BBChess.Protocol.Process ("new");
         BBChess.Protocol.Process ("force");
         BBChess.Protocol.Process ("ping 42");
         BBChess.Protocol.Process ("level 40 5 1");
         BBChess.Protocol.Process ("usermove e2e4");
         BBChess.Protocol.Process ("e2e4");
         Assert (N_Lines = 0, "XBoard commands are ignored (no output)");
         Assert (BBChess.Protocol.Position_Of = P_Before,
                 "XBoard commands leave the position untouched");
      end;

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

      -- Restore the engine-wide search globals this dispatch test touched:
      -- "uci" turned the UCI output on, and "setoption Threads 3" changed the
      -- thread count. Left set, they would make the later search tests print
      -- "info" lines and run multi-threaded (non-deterministic node counts).
      Set_UCI_Mode (False);
      Set_Threads (1);
      Set_Search_Param ("S_CONTEMPT", 0);
      Reset_Search;

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
      Test_Dispatch;
      Ada.Text_IO.Put_Line ("protocol tests OK");
   end Run;

end BBChess.Protocol.Self_Tests;
