--
--  BabaChess : protocol driver (body)
--
--  This is the former command loop of babachess.adb, moved here almost
--  verbatim: the session state and the dispatch are unchanged, only the
--  output goes through the installed Line_Writer instead of Ada.Text_IO.
--

with Ada.Characters.Handling;
with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Unbounded;

with Interfaces;

with BBChess.Board;
use BBChess.Board;
with BBChess.Moves;
use BBChess.Moves;
with BBChess.Pieces;
use BBChess.Pieces;

with BBChess.Hash;
with BBChess.Fen;
use BBChess.Fen;
with BBChess.Movegen;
use BBChess.Movegen;
with BBChess.Perft;
with BBChess.Notation;
use BBChess.Notation;
with BBChess.Search;
use BBChess.Search;
with BBChess.Clocks;
use BBChess.Clocks;
with BBChess.Polyglot;
use BBChess.Polyglot;
with BBChess.Syzygy;
with BBChess.Text;
use BBChess.Text;
with BBChess.Eval;
use BBChess.Eval;

with BBChess.Protocol.UCI;

package body BBChess.Protocol is

   use Ada.Strings.Unbounded;

   --  Output writer, installed by Initialize. In production this is
   --  BBChess.Search.Locked_Put_Line (shared console lock); in the self test
   --  it is a capturing procedure.
   Writer : Line_Writer := null;

   procedure Emit (S : in String) is
   begin
      if Writer /= null then
         Writer.all (S);
      end if;
   end Emit;

   -------------
   --  State  --
   -------------

   Pos      : Position_Type := Start_Position;
   UCI_Mode : Boolean := False;
   Quit     : Boolean := False;

   Game_Keys : BBChess.Search.Game_Key_Array := (others => 0);
   Game_N    : Natural := 0;

   Fixed_Time     : Boolean := False;
   Move_Time      : Duration := 1.0;
   Clock_Left     : Duration := 0.0;
   Time_Increment : Duration := 0.0;
   Moves_To_Go    : Natural := 0;
   --  Time the engine hands back to the GUI/OS on every move (I/O, process
   --  scheduling, GUI lag). Subtracted from the clock before the budget is
   --  computed; the UCI "Move Overhead" option sets it in milliseconds.
   Move_Overhead  : Duration := 0.010;
   Max_Depth      : Natural := 64;

   Book_Max_Ply : constant := 16;
   Own_Book     : Boolean := True;

   --  UCI_LimitStrength / UCI_Elo. When the limiter is on, a search is
   --  capped at a node budget derived from the requested Elo (see
   --  Nodes_For_Elo): a time-independent strength knob, so the engine can
   --  play against humans and gives the project its own anchor scale instead
   --  of borrowing another engine's rating.
   Limit_Strength : Boolean := False;
   Elo_Limit      : Natural := 2_800;

   --  Node budget per move for a requested Elo, interpolated between the
   --  anchor points below (1200 Elo .. 2800 Elo). The curve is deliberately
   --  approximate: it is a monotone mapping, not a measured Elo calibration,
   --  so an UCI_Elo value is a playing-strength setting rather than a rating
   --  claim. 2800 gives 10M nodes, effectively full strength at normal time
   --  controls.
   Strength_Nodes : constant array (0 .. 8) of Node_Count_Type :=
     (1_000, 3_000, 10_000, 30_000, 100_000,
      300_000, 1_000_000, 3_000_000, 10_000_000);

   function Nodes_For_Elo (Elo : in Natural) return Node_Count_Type is
      E     : constant Natural := Natural'Max (1_200, Natural'Min (2_800, Elo));
      Idx   : constant Natural := E / 200 - 6;
      Rest  : constant Natural := E mod 200;
   begin
      if Idx >= 8 then
         return Strength_Nodes (8);
      end if;
      return Strength_Nodes (Idx)
        + (Strength_Nodes (Idx + 1) - Strength_Nodes (Idx))
          * Node_Count_Type (Rest) / 200;
   end Nodes_For_Elo;

   -----------------------
   --  Game history     --
   -----------------------

   procedure Push_Game_Key (Key : in Bitboard) is
   begin
      if Game_N = BBChess.Search.Max_Game_Keys then
         for I in 1 .. Game_N - 1 loop
            Game_Keys (I - 1) := Game_Keys (I);
         end loop;
         Game_N := Game_N - 1;
      end if;
      Game_Keys (Game_N) := Key;
      Game_N := Game_N + 1;
   end Push_Game_Key;

   procedure Record_Current_Key is
      K : constant Bitboard := BBChess.Hash.Compute (Pos);
   begin
      if Game_N = 0 or else Game_Keys (Game_N - 1) /= K then
         Push_Game_Key (K);
      end if;
   end Record_Current_Key;

   procedure Sync_Game_History is
   begin
      BBChess.Search.Set_Game_History (Game_Keys, Game_N);
   end Sync_Game_History;

   procedure Reset_Game_History is
   begin
      Game_N := 0;
      Record_Current_Key;
   end Reset_Game_History;

   -----------------------
   --  Time allocation  --
   -----------------------

   function Time_For_Next_Move return BBChess.Clocks.Allocation is
      --  The overhead is taken off the clock, not off the budget: it stays an
      --  absolute amount of time even when the remaining clock is small.
      Usable : constant Duration := Clock_Left - Move_Overhead;
   begin
      if Fixed_Time then
         return Exact (Move_Time);
      end if;
      if Clock_Left <= 0.0 or else Usable <= 0.0 then
         return Exact (Move_Time);
      end if;
      return Clock_Based
        (Usable, Time_Increment, Moves_To_Go,
         Policy =>
           (Moves_Default => BBChess.Search.Tm_Moves_Default,
            Hard_Mult     => Duration (BBChess.Search.Tm_Hard_Hundredths) / 100.0,
            Inc_Frac      => Duration (BBChess.Search.Tm_Inc_Hundredths) / 100.0));
   end Time_For_Next_Move;

   ---------------
   --  Opening book --
   ---------------

   function Try_Book (Move : out Move_Type) return Boolean is
      M : Move_Type;
   begin
      Move := Empty_Move;
      if not Own_Book or else not BBChess.Polyglot.Book_Loaded then
         return False;
      end if;
      if Game_N = 0 or else Game_N - 1 > Book_Max_Ply then
         return False;
      end if;
      if BBChess.Polyglot.Probe (Pos, M) and then M /= Empty_Move then
         Move := M;
         return True;
      end if;
      return False;
   end Try_Book;

   procedure Configure_Book (Path : in String) is
      Status : constant BBChess.Polyglot.Load_Status :=
        BBChess.Polyglot.Open_Book (Path);
   begin
      --  An explicit request (--book / setoption BookFile) that fails is
      --  reported. Before Initialize the writer is null, so the CLI form is
      --  silently accepted (nothing to print to yet).
      if Status /= BBChess.Polyglot.Loaded then
         Emit ("info string " & BBChess.Polyglot.Status_Message (Status, Path));
      end if;
   end Configure_Book;

   procedure Configure_Syzygy (Path : in String) is
      Ok : Boolean;
   begin
      BBChess.Syzygy.Init (Path, Ok);
   end Configure_Syzygy;

   --  Tablebase autoconfiguration, the Syzygy counterpart of
   --  Load_Default_Book: probe the conventional locations so a user who
   --  dropped the .rttb files in ~/.babachess/syzygy (or ./syzygy) gets DTZ
   --  play without any setoption.  Best-effort and silent, like the book
   --  search: a missing candidate is the normal case.  Only directories that
   --  actually contain tablebase files are considered, so an empty leftover
   --  directory never shadows a real one.
   procedure Load_Default_Syzygy is
      Exe : constant String := Ada.Command_Line.Command_Name;

      function Exe_Dir return String is
         Slash : Natural := 0;
      begin
         for I in Exe'Range loop
            if Exe (I) = '/' then
               Slash := I;
            end if;
         end loop;
         if Slash = 0 then
            return ".";
         end if;
         return Exe (Exe'First .. Slash - 1);
      end Exe_Dir;

      D    : constant String := Exe_Dir;
      Home : constant String :=
        (if Ada.Environment_Variables.Exists ("HOME")
         then Ada.Environment_Variables.Value ("HOME") else "");

      function Has_Tablebase (Dir : in String) return Boolean is
         use Ada.Directories;
         Search : Search_Type;
         E      : Directory_Entry_Type;
         Found  : Boolean := False;
      begin
         if Dir'Length = 0 or else not Exists (Dir)
           or else Kind (Dir) /= Directory
         then
            return False;
         end if;
         Start_Search (Search, Dir, "*.rtbw");
         while More_Entries (Search) loop
            Get_Next_Entry (Search, E);
            if Kind (E) = Ordinary_File then
               Found := True;
               exit;
            end if;
         end loop;
         End_Search (Search);
         return Found;
      end Has_Tablebase;

      Candidates : constant array (1 .. 4) of Unbounded_String :=
        (1 => To_Unbounded_String ("syzygy"),
         2 => To_Unbounded_String (D & "/syzygy"),
         3 => To_Unbounded_String (Home & "/.babachess/syzygy"),
         4 => To_Unbounded_String (D & "/../syzygy"));
   begin
      --  An explicit setoption SyzygyPath (or --syzygy) wins: Fathom keeps
      --  the paths given at its last Init, so probing here would clobber it.
      if BBChess.Syzygy.Enabled then
         return;
      end if;
      for C in Candidates'Range loop
         declare
            Path : constant String := To_String (Candidates (C));
            Ok   : Boolean;
         begin
            if Has_Tablebase (Path) then
               BBChess.Syzygy.Init (Path, Ok);
               if Ok then
                  return;
               end if;
            end if;
         end;
      end loop;
   end Load_Default_Syzygy;

   procedure Load_Default_Book is
      Exe : constant String := Ada.Command_Line.Command_Name;

      function Exe_Dir return String is
         Slash : Natural := 0;
      begin
         for I in Exe'Range loop
            if Exe (I) = '/' then
               Slash := I;
            end if;
         end loop;
         if Slash = 0 then
            return ".";
         end if;
         return Exe (Exe'First .. Slash - 1);
      end Exe_Dir;

      D    : constant String := Exe_Dir;
      Home : constant String :=
        (if Ada.Environment_Variables.Exists ("HOME")
         then Ada.Environment_Variables.Value ("HOME") else "");
      Candidates : constant array (1 .. 6) of Unbounded_String :=
        (1 => To_Unbounded_String ("books/book.bin"),
         2 => To_Unbounded_String (D & "/books/book.bin"),
         3 => To_Unbounded_String (D & "/../books/book.bin"),
         4 => To_Unbounded_String (Home & "/.babachess/book.bin"),
         5 => To_Unbounded_String ("book.bin"),
         6 => To_Unbounded_String (D & "/book.bin"));
   begin
      if BBChess.Polyglot.Book_Loaded then
         return;
      end if;
      --  Probing the conventional locations is best-effort: a missing
      --  candidate is the normal case, so nothing is reported here (unlike an
      --  explicit --book / setoption BookFile request, which does report).
      for C in Candidates'Range loop
         if BBChess.Polyglot.Open_Book (To_String (Candidates (C)))
              = BBChess.Polyglot.Loaded
         then
            return;
         end if;
      end loop;
   end Load_Default_Book;

   -----------------------------
   --  Asynchronous UCI       --
   -----------------------------

   protected type UCI_Status is
      procedure Set_Busy (B : in Boolean);
      function Busy return Boolean;
   private
      Is_Busy : Boolean := False;
   end UCI_Status;

   protected body UCI_Status is
      procedure Set_Busy (B : in Boolean) is
      begin
         Is_Busy := B;
      end Set_Busy;

      function Busy return Boolean is
      begin
         return Is_Busy;
      end Busy;
   end UCI_Status;

   UCI_Busy : UCI_Status;

   --  "ponderhit" arrives from the command loop while the search task owns
   --  the best move: a protected flag carries the event across the task
   --  boundary without polling shared unprotected state.
   protected type Ponder_State is
      procedure Hit;
      procedure Clear;
      function  Hitting return Boolean;
   private
      H : Boolean := False;
   end Ponder_State;

   protected body Ponder_State is
      procedure Hit is
      begin
         H := True;
      end Hit;

      procedure Clear is
      begin
         H := False;
      end Clear;

      function Hitting return Boolean is
      begin
         return H;
      end Hitting;
   end Ponder_State;

   Ponder_Hit : Ponder_State;

   task type UCI_Search_Task is
      entry Start (P : in Position_Type; D : in Natural;
                   Soft : in Duration; Hard : in Duration;
                   Node_Cap : in BBChess.Search.Node_Count_Type;
                   Infinite : in Boolean; Ponder : in Boolean;
                   Moves : in Move_List; Num_Moves : in Natural);
      entry Stop_Now;
   end UCI_Search_Task;

   task body UCI_Search_Task is
      Position : Position_Type;
      M        : Move_Type;
      Depth    : Natural;
      Soft_Alloc : Duration;
      Hard_Alloc : Duration;
      Cap      : BBChess.Search.Node_Count_Type;
      Inf      : Boolean;
      Pond     : Boolean;
   begin
      loop
         select
            accept Start (P : in Position_Type; D : in Natural;
                          Soft : in Duration; Hard : in Duration;
                          Node_Cap : in BBChess.Search.Node_Count_Type;
                          Infinite : in Boolean; Ponder : in Boolean;
                          Moves : in Move_List; Num_Moves : in Natural)
            do
               Inf := Infinite;
               Pond := Ponder;
               Position := P;
               Depth  := D;
               Soft_Alloc := Soft;
               Hard_Alloc := Hard;
               Cap    := Node_Cap;
               --  Installed here, inside the rendezvous: the previous search
               --  has ended and no worker is running, so the filter is never
               --  written while another search reads it.
               Set_Search_Moves (Moves, Num_Moves);
               Ponder_Hit.Clear;
               UCI_Busy.Set_Busy (True);
               Clear_Stop;
            end Start;

            begin
               if Cap > 0 then
                  M := Best_Move (Position, Depth, Hard_Alloc, Cap);
               else
                  M := Best_Move (Position, Depth, Soft_Alloc, Hard_Alloc);
               end if;
            exception
               when E : others =>
                  --  A search must still answer (bestmove 0000), but the
                  --  failure is logged on stderr instead of vanishing: a
                  --  silent crash would look like an unexplained slowdown.
                  BBChess.Search.Log_Worker_Exception
                    ("UCI search task exception", E);
                  M := Empty_Move;
            end;

            --  Hold the best move until the opponent actually plays it
            --  ("ponderhit") or the GUI calls it off ("stop"/"quit"). The
            --  search itself runs with the normal budget, so the time spent
            --  pondering is not reclaimed: on ponderhit the move is emitted
            --  at once instead of being re-timed.
            while (Inf or Pond)
              and then not Stop_Requested
              and then not (Pond and then Ponder_Hit.Hitting)
            loop
               delay 0.005;
            end loop;

            UCI_Busy.Set_Busy (False);
            if M = Empty_Move then
               Emit ("bestmove 0000");
            else
               Emit ("bestmove " & To_String (M));
            end if;
         or
            accept Stop_Now;
            exit;
         or
            terminate;
         end select;
      end loop;
   end UCI_Search_Task;

   type UCI_Search_Task_Access is access UCI_Search_Task;

   Active_Task : UCI_Search_Task_Access := null;

   procedure Ensure_UCI_Task is
   begin
      if Active_Task = null then
         Active_Task := new UCI_Search_Task;
      end if;
   end Ensure_UCI_Task;

   procedure Shutdown_UCI_Search is
   begin
      if Active_Task /= null then
         if UCI_Busy.Busy then
            Request_Stop;
         end if;
         Active_Task.Stop_Now;
         Active_Task := null;
      end if;
   end Shutdown_UCI_Search;

   procedure Shutdown is
   begin
      Shutdown_UCI_Search;
   end Shutdown;

   -----------------
   --  UCI position --
   -----------------

   procedure Apply_UCI_Position (Par : in String) is
      T1 : constant String := Token (Par, 1);
      I  : Natural := 1;
      N  : constant Natural := UCI.Token_Count (Par);
      M  : Move_Type;
      U  : Undo_Info;
   begin
      if T1 = "startpos" then
         Pos := Start_Position;
         I := 2;
      elsif T1 = "fen" then
         declare
            Fen  : String (1 .. 256);
            L    : Natural := 0;
            Over : Boolean := False;
         begin
            for K in 2 .. 7 loop
               declare
                  Tok : constant String := Token (Par, K);
               begin
                  exit when Tok'Length = 0 or else Tok = "moves";
                  if L > 0 then
                     Append_Bounded (Fen, L, " ", Over);
                  end if;
                  Append_Bounded (Fen, L, Tok, Over);
               end;
            end loop;
            if Over then
               Emit ("info string bad FEN");
               return;
            else
               begin
                  Load (Pos, Fen (1 .. L));
               exception
                  when Constraint_Error =>
                     Emit ("info string bad FEN");
                     return;
               end;
            end if;
         end;
         I := 2;
      else
         return;
      end if;

      Reset_Game_History;
      while I <= N loop
         exit when Token (Par, I) = "moves";
         I := I + 1;
      end loop;
      I := I + 1;
      while I <= N loop
         M := From_String (Pos, Token (Par, I));
         if M = Empty_Move then
            Emit ("info string unknown move " & Token (Par, I));
            exit;
         else
            Make_Move (Pos, M, U);
            Record_Current_Key;
         end if;
         I := I + 1;
      end loop;
   end Apply_UCI_Position;

   ------------------
   --  UCI "d"     --
   ------------------

   --  Unofficial but expected by every engine author: print the position as a
   --  board diagram and as a FEN, so a session can be inspected without a GUI.
   procedure Handle_UCI_Display is
      P : Piece_Type;

      function Letter (X : in Piece_Type) return Character is
        (case Kind (X) is
           when Pawn   => (if Color (X) = White then 'P' else 'p'),
           when Knight => (if Color (X) = White then 'N' else 'n'),
           when Bishop => (if Color (X) = White then 'B' else 'b'),
           when Rook   => (if Color (X) = White then 'R' else 'r'),
           when Queen  => (if Color (X) = White then 'Q' else 'q'),
           when King   => (if Color (X) = White then 'K' else 'k'));

      function Img (N : in Natural) return String is
         S : constant String := Natural'Image (N);
      begin
         return S (S'First + 1 .. S'Last);
      end Img;
   begin
      Emit (" +---+---+---+---+---+---+---+---+");
      for Rank in reverse 0 .. 7 loop
         declare
            Line : Unbounded_String := Null_Unbounded_String;
         begin
            for File in 0 .. 7 loop
               Append (Line, " | ");
               if Piece_At (Pos, Rank * 8 + File, P) then
                  Append (Line, Letter (P));
               else
                  Append (Line, '.');
               end if;
            end loop;
            Append (Line, " | " & Img (Rank + 1));
            Emit (To_String (Line));
            Emit (" +---+---+---+---+---+---+---+---+");
         end;
      end loop;
      Emit ("   a   b   c   d   e   f   g   h");
      Emit ("Fen: " & BBChess.Fen.To_String (Pos));
      Emit ((if Pos.Side = White then "White" else "Black") & " to move");
      Emit ("Castling: "
            & (if Pos.Castle (White, King_Side) then "K" else "")
            & (if Pos.Castle (White, Queen_Side) then "Q" else "")
            & (if Pos.Castle (Black, King_Side) then "k" else "")
            & (if Pos.Castle (Black, Queen_Side) then "q" else "")
            & (if not (Pos.Castle (White, King_Side)
                       or else Pos.Castle (White, Queen_Side)
                       or else Pos.Castle (Black, King_Side)
                       or else Pos.Castle (Black, Queen_Side))
               then "-" else ""));
      Emit ("Key: " & Hex_Image (Interfaces.Unsigned_64
                                 (BBChess.Hash.Compute (Pos))));
   end Handle_UCI_Display;

   -----------------
   --  UCI eval   --
   -----------------

   --  Per-term static evaluation (unofficial, the same idea as Stockfish's
   --  "eval"): the engine's score is a sum of named terms, so printing them
   --  turns "why does this position score X" into one command instead of a
   --  bisect. Values are White-positive centipawns, each term blended at the
   --  current phase; because the engine blends the tapered *sum* once, the
   --  rounded terms may differ from the total by a centipawn or two.
   procedure Handle_UCI_Eval is
      Terms : Eval_Breakdown;
      Total : constant Score_Type := Breakdown (Pos, Terms);

      function Signed (N : in Integer) return String is
         S : constant String := Integer'Image (N);
      begin
         if N < 0 then
            return S;
         end if;
         return "+" & S (S'First + 1 .. S'Last);
      end Signed;

      function Pad (S : in String) return String is
        (S & (1 .. Natural'Max (0, 22 - S'Length) => ' '));

      procedure Row (Label : in String; Value : in Integer) is
      begin
         Emit (Pad ("  " & Label) & Signed (Value));
      end Row;

      function Img (N : in Natural) return String is
         S : constant String := Natural'Image (N);
      begin
         return S (S'First + 1 .. S'Last);
      end Img;
   begin
      Emit ("Static: " & Signed (Total) & " (White's point of view, phase "
            & Img (Game_Phase (Pos)) & "/100)");
      Row ("material + PST", Terms (Material_Term));
      Row ("bishop pair", Terms (Bishop_Pair));
      Row ("mobility & threats", Terms (Mobility));
      Row ("connected rooks", Terms (Connected_Rooks));
      Row ("pawn structure", Terms (Pawn_Structure));
      Row ("pawn threats", Terms (Pawn_Threats));
      Row ("outposts", Terms (Outpost));
      Row ("king activity", Terms (King_Activity));
      Row ("king safety", Terms (King_Safety));
      Row ("hanging pieces", Terms (Hanging));
      Row ("drawish scaling", Terms (Drawish_Scale));
      Row ("minor imbalance", Terms (Minor_Imbalance));
      Emit ("Evaluate: " & Signed (Evaluate (Pos))
            & " (side to move, tempo " & Signed (Tempo) & ")");
   end Handle_UCI_Eval;

   ------------------
   --  UCI perft   --
   ------------------

   --  "go perft N": per-root-move leaf counts then the total, the layout other
   --  engines print. Perft.Nodes returns a Natural, so a depth whose count
   --  exceeds 2**31 is refused rather than reported wrong.
   procedure Handle_UCI_Perft (Depth : in Natural) is
      Work  : Position_Type := Pos;
      Total : Natural := 0;

      function Img (N : in Natural) return String is
         S : constant String := Natural'Image (N);
      begin
         return S (S'First + 1 .. S'Last);
      end Img;
   begin
      if Depth = 0 or else Depth > 7 then
         Emit ("info string perft: depth must be 1 .. 7");
         return;
      end if;

      declare
         Moves : Move_List;
         Count : Natural;
      begin
         Generate_Legal_Moves (Work, Moves, Count);
         for I in 1 .. Count loop
            declare
               Undo : Undo_Info;
               N    : Natural;
            begin
               Make_Move (Work, Moves (I), Undo);
               N := BBChess.Perft.Nodes (Work, Depth - 1);
               Unmake_Move (Work, Moves (I), Undo);
               Total := Total + N;
               Emit ("info string " & To_String (Moves (I)) & " " & Img (N));
            end;
         end loop;
      end;
      Emit ("info string nodes searched " & Img (Total));
      Emit ("info string perft " & Img (Depth) & " " & Img (Total));
   end Handle_UCI_Perft;

   -----------------
   --  UCI go      --
   -----------------

   procedure Handle_UCI_Go (Par : in String) is
      Go : constant UCI.Go_Params := UCI.Parse_Go (Par);
      --  Root move filter for this search ("go searchmoves"); empty means the
      --  full list. Installed by the search task at the start rendezvous.
      Filter_Moves : Move_List;
      Filter_N     : Natural := 0;
      --  "go mate N": a proven mate in N moves ends the search, and 2N plies
      --  is the depth cap when the GUI did not give one.
      Mate_Requested : constant Boolean :=
        Go.Has_Mate and then Go.Mate_Moves > 0;
      --  UCI_LimitStrength: a node cap derived from UCI_Elo, applied in
      --  addition to whatever the GUI sent (and only when the search is not
      --  open-ended).
      Strength_Cap : constant Node_Count_Type :=
        (if Limit_Strength and then not Go.Infinite and then not Go.Ponder
         then Nodes_For_Elo (Elo_Limit) else 0);
      Cap          : Node_Count_Type := Go.Nodes;
   begin
      --  "go perft N": leaf count instead of a search (unofficial, but the
      --  spelling other engines accept). No bestmove is emitted.
      if Go.Has_Perft then
         Handle_UCI_Perft (Go.Perft_Depth);
         return;
      end if;

      --  "go searchmoves ...": restrict the root list for this search only.
      --  The tokens are resolved against the current position; an unknown or
      --  illegal move is reported and dropped.
      if Go.Has_Searchmoves then
         declare
            Text : constant String := To_String (Go.Searchmoves);
            N    : constant Natural := UCI.Token_Count (Text);
         begin
            for I in 1 .. N loop
               declare
                  M : constant Move_Type := From_String (Pos, Token (Text, I));
               begin
                  if M = Empty_Move then
                     Emit ("info string searchmoves: unknown move "
                           & Token (Text, I));
                  elsif Filter_N < Filter_Moves'Length then
                     Filter_N := Filter_N + 1;
                     Filter_Moves (Filter_N) := M;
                  end if;
               end;
            end loop;
         end;
      end if;

      Fixed_Time := False;
      Clock_Left := 0.0;
      Time_Increment := 0.0;
      Moves_To_Go := 0;
      Max_Depth := 64;

      if Go.Has_Movetime then
         Fixed_Time := True;
         Move_Time := Go.Movetime;
      end if;
      if Pos.Side = White then
         Clock_Left := Go.Wtime;
         Time_Increment := Go.Winc;
      else
         Clock_Left := Go.Btime;
         Time_Increment := Go.Binc;
      end if;
      Moves_To_Go := Go.Movestogo;
      Max_Depth := Go.Depth;

      if Mate_Requested then
         Set_Mate_Limit (Go.Mate_Moves);
         if not Go.Has_Depth then
            Max_Depth := 2 * Go.Mate_Moves;
         else
            Max_Depth := Natural'Min (Max_Depth, 2 * Go.Mate_Moves);
         end if;
      else
         Set_Mate_Limit (0);
      end if;

      if Strength_Cap > 0 and then (Cap = 0 or else Cap > Strength_Cap) then
         Cap := Strength_Cap;
      end if;

      if not Go.Infinite and then not Go.Ponder
        and then Cap = 0 and then not UCI_Busy.Busy
        and then Filter_N = 0
        and then not Mate_Requested
      then
         declare
            BM : Move_Type;
         begin
            if Try_Book (BM) then
               Emit ("bestmove " & To_String (BM));
               return;
            end if;
         end;
      end if;

      declare
         Alloc : BBChess.Clocks.Allocation;
      begin
         if Go.Infinite or else Go.Nodes > 0
           or else (Go.Has_Depth and then Clock_Left <= 0.0
                    and then not Fixed_Time)
           or else (Mate_Requested and then Clock_Left <= 0.0
                    and then not Fixed_Time)
           or else (Strength_Cap > 0 and then Clock_Left <= 0.0
                    and then not Fixed_Time)
         then
            Alloc := (Soft => 0.0, Hard => 0.0);
         else
            Alloc := Time_For_Next_Move;
         end if;

         if UCI_Busy.Busy then
            Request_Stop;
         end if;

         Sync_Game_History;

         Ensure_UCI_Task;
         Active_Task.Start (Pos, Max_Depth, Alloc.Soft, Alloc.Hard,
                            Cap, Go.Infinite, Go.Ponder,
                            Filter_Moves, Filter_N);
      end;
   end Handle_UCI_Go;

   -------------------
   --  UCI handshake --
   -------------------

   procedure UCI_Handshake is
      Size : constant String :=
        Trim_Both (Natural'Image (Transposition_Size_MB));
   begin
      Emit ("id name BabaChess " & BabaChess_Version);
      Emit ("id author claurence57");
      Emit ("option name Hash type spin default " & Size
            & " min 1 max 1024");
      Emit ("option name Clear Hash type button");
      Emit ("option name Threads type spin default 1 min 1 max 16");
      Emit ("option name Move Overhead type spin default 10 min 0 max 5000");
      Emit ("option name OwnBook type check default true");
      Emit ("option name BookFile type string default books/book.bin");
      Emit ("option name SyzygyPath type string default <empty>");
      Emit ("option name Syzygy50MoveRule type check default true");
      Emit ("option name Contempt type spin default 0 min -100 max 100");
      Emit ("option name MultiPV type spin default 1 min 1 max "
            & Trim_Both (Natural'Image (Max_MultiPV)));
      Emit ("option name UCI_LimitStrength type check default false");
      Emit ("option name UCI_Elo type spin default 2800 min 1200 max 2800");
      Emit ("uciok");
   end UCI_Handshake;

   -------------------
   --  UCI setoption --
   -------------------

   procedure Handle_UCI_Setoption (Par : in String) is
      use Ada.Characters.Handling;
      Opt : constant UCI.Setoption_Params := UCI.Parse_Setoption (Par);
      Name  : constant String := To_String (Opt.Name);
      Value : constant String := To_String (Opt.Value);

      --  Dispatch key: the option name with its spaces removed, so that both
      --  "SyzygyPath" (what this engine advertises) and "Syzygy Path" (what a
      --  user may type, and what some GUIs send) reach the same branch.
      function No_Spaces (S : in String) return String is
         R : String (1 .. S'Length);
         N : Natural := 0;
      begin
         for C of S loop
            if C /= ' ' then
               N := N + 1;
               R (N) := C;
            end if;
         end loop;
         return R (1 .. N);
      end No_Spaces;

      Key : constant String := No_Spaces (Name);
   begin
      if UCI_Busy.Busy then
         Emit ("info string setoption ignored while searching");
      elsif Key = "clearhash" then
         Reset_Search;
      elsif Key = "hash" and then Opt.Is_Value then
         Set_Transposition_Size (UCI.Parse_Natural (Value, 0));
         Emit ("info string Hash size "
               & Trim_Both (Natural'Image (Transposition_Size_MB)) & " MB");
         Reset_Search;
      elsif Key = "moveoverhead" and then Opt.Is_Value then
         Move_Overhead :=
           Duration (Natural'Min (5_000, UCI.Parse_Natural (Value, 10))) / 1000.0;
      elsif Key = "threads" and then Opt.Is_Value then
         Set_Threads (UCI.Parse_Natural (Value, 1));
      elsif Key = "ownbook" and then Opt.Is_Value then
         Own_Book := To_Lower (Value) = "true";
      elsif Key = "bookfile" and then Opt.Is_Value then
         Configure_Book (Value);
      elsif Key = "syzygypath" and then Opt.Is_Value then
         Configure_Syzygy (Value);
      elsif Key = "syzygy50moverule" and then Opt.Is_Value then
         BBChess.Syzygy.Set_Fifty_Move_Rule (To_Lower (Value) = "true");
      elsif Key = "contempt" and then Opt.Is_Value then
         --  Set_Search_Param clamps to the advertised range (-100 .. 100).
         Set_Search_Param ("S_CONTEMPT", UCI.Parse_Integer (Value, 0));
      elsif Key = "multipv" and then Opt.Is_Value then
         Set_MultiPV (UCI.Parse_Natural (Value, 1));
      elsif Key = "uci_limitstrength" and then Opt.Is_Value then
         Limit_Strength := To_Lower (Value) = "true";
      elsif Key = "uci_elo" and then Opt.Is_Value then
         Elo_Limit := Natural'Max
           (1_200, Natural'Min (2_800, UCI.Parse_Natural (Value, 2_800)));
      end if;
   end Handle_UCI_Setoption;

   -------------
   -- Process --
   -------------

   procedure Process (Line : in String) is
      Trimmed : constant String := Trim_Both (Line);
   begin
      if Trimmed'Length = 0 then
         return;
      end if;

      declare
         Cmd_Buf : String (1 .. 64);
         Cmd_L   : Natural;
         Par_Buf : String (1 .. 8192);
         Par_L   : Natural;
      begin
         Split_Command (Trimmed, Cmd_Buf, Cmd_L, Par_Buf, Par_L);

         declare
            Cmd : constant String := Cmd_Buf (1 .. Cmd_L);
            Par : constant String := Par_Buf (1 .. Par_L);
         begin
            if Cmd = "uci" then
               UCI_Mode := True;
               Set_UCI_Mode (True);
               UCI_Handshake;

            elsif Cmd = "isready" and then UCI_Mode then
               Emit ("readyok");

            elsif Cmd = "ucinewgame" and then UCI_Mode then
               if UCI_Busy.Busy then
                  Emit ("info string ucinewgame ignored while searching");
               else
                  Reset_Search;
                  Reset_Game_History;
               end if;

            elsif Cmd = "position" and then UCI_Mode then
               Apply_UCI_Position (Par);

            elsif Cmd = "go" and then UCI_Mode then
               Handle_UCI_Go (Par);

            elsif Cmd = "stop" and then UCI_Mode then
               if UCI_Busy.Busy then
                  Request_Stop;
               end if;

            elsif Cmd = "ponderhit" and then UCI_Mode then
               --  The predicted move was played: release the held best move.
               Ponder_Hit.Hit;

            elsif UCI_Mode
              and then (Cmd = "debug" or else Cmd = "register")
            then
               null;

            --  Unofficial "d": print the position (board diagram + FEN).
            elsif Cmd = "d" and then UCI_Mode then
               Handle_UCI_Display;

            elsif Cmd = "eval" and then UCI_Mode then
               Handle_UCI_Eval;

            elsif Cmd = "setoption" and then UCI_Mode then
               Handle_UCI_Setoption (Par);

            elsif Cmd = "quit" or else Cmd = "exit" then
               Quit := True;

            --  Anything else (including the former XBoard commands) is
            --  ignored: the engine speaks UCI only.
            end if;
         end;
      end;
   end Process;

   ----------------
   --  Commands  --
   ----------------

   procedure Initialize (W : in Line_Writer) is
   begin
      Writer := W;
      Reset;
   end Initialize;

   procedure Reset is
   begin
      Pos := Start_Position;
      UCI_Mode := False;
      Quit := False;
      Game_N := 0;
      Fixed_Time := False;
      Move_Time := 1.0;
      Clock_Left := 0.0;
      Time_Increment := 0.0;
      Moves_To_Go := 0;
      Max_Depth := 64;
      Own_Book := True;
      Limit_Strength := False;
      Elo_Limit := 2_800;
      Set_MultiPV (1);
      Set_Mate_Limit (0);
      BBChess.Syzygy.Set_Fifty_Move_Rule (True);
   end Reset;

   function Exit_Requested return Boolean is
   begin
      return Quit;
   end Exit_Requested;

   ----------------------------
   --  Observability (tests) --
   ----------------------------

   function Position_Of return Position_Type is
   begin
      return Pos;
   end Position_Of;

   function Key_Of return Bitboard is
   begin
      return Pos.Key;
   end Key_Of;

   function Is_UCI return Boolean is
   begin
      return UCI_Mode;
   end Is_UCI;

   function Busy return Boolean is
   begin
      return UCI_Busy.Busy;
   end Busy;

end BBChess.Protocol;
