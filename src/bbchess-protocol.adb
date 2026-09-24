--
--  BabaChess : protocol driver (body)
--
--  This is the former command loop of babachess.adb, moved here almost
--  verbatim: the session state and the dispatch are unchanged, only the
--  output goes through the installed Line_Writer instead of Ada.Text_IO.
--

with Ada.Characters.Handling;
with Ada.Command_Line;
with Ada.Environment_Variables;
with Ada.Strings.Unbounded;

with BBChess.Board;
use BBChess.Board;
with BBChess.Moves;
use BBChess.Moves;
with BBChess.Pieces;
use BBChess.Pieces;

with BBChess.Hash;
with BBChess.Fen;
use BBChess.Fen;
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

with BBChess.Protocol.UCI;
with BBChess.Protocol.XBoard;

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

   Pos         : Position_Type := Start_Position;
   Engine_Side : Color_Type := Black;
   Force       : Boolean := True;
   Protocol    : Boolean := False;
   UCI_Mode    : Boolean := False;
   Quit        : Boolean := False;

   Game_Keys : BBChess.Search.Game_Key_Array := (others => 0);
   Game_N    : Natural := 0;

   Fixed_Time     : Boolean := False;
   Move_Time      : Duration := 1.0;
   Clock_Left     : Duration := 0.0;
   Time_Increment : Duration := 0.0;
   Moves_To_Go    : Natural := 0;
   Moves_Per_Session : Natural := 0;
   Max_Depth      : Natural := 64;

   Book_Max_Ply : constant := 16;
   Own_Book     : Boolean := True;

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
   begin
      if Fixed_Time then
         return Exact (Move_Time);
      end if;
      if Clock_Left <= 0.0 then
         return Exact (Move_Time);
      end if;
      return Clock_Based (Clock_Left, Time_Increment, Moves_To_Go);
   end Time_For_Next_Move;

   procedure Consume_Move_Count is
   begin
      if Moves_To_Go > 0 then
         Moves_To_Go := Moves_To_Go - 1;
         if Moves_To_Go = 0 then
            Moves_To_Go := Moves_Per_Session;
         end if;
      end if;
   end Consume_Move_Count;

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

   task type UCI_Search_Task is
      entry Start (P : in Position_Type; D : in Natural;
                   Soft : in Duration; Hard : in Duration;
                   Node_Cap : in BBChess.Search.Node_Count_Type;
                   Infinite : in Boolean);
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
   begin
      loop
         select
            accept Start (P : in Position_Type; D : in Natural;
                          Soft : in Duration; Hard : in Duration;
                          Node_Cap : in BBChess.Search.Node_Count_Type;
                          Infinite : in Boolean)
            do
               Inf := Infinite;
               Position := P;
               Depth  := D;
               Soft_Alloc := Soft;
               Hard_Alloc := Hard;
               Cap    := Node_Cap;
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

            while Inf and then not Stop_Requested loop
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

   ----------------
   --  XBoard play --
   ----------------

   procedure Play_If_My_Turn is
   begin
      if Protocol and then not Force and then Pos.Side = Engine_Side then
         Record_Current_Key;

         declare
            BM   : Move_Type;
            Undo : Undo_Info;
         begin
            if Try_Book (BM) then
               Emit ("move " & To_String (BM));
               Make_Move (Pos, BM, Undo);
               Record_Current_Key;
               Consume_Move_Count;
               return;
            end if;
         end;

         Sync_Game_History;
         declare
            Alloc : constant BBChess.Clocks.Allocation := Time_For_Next_Move;
            M     : constant Move_Type :=
              Best_Move (Pos, Max_Depth, Alloc.Soft, Alloc.Hard);
            Undo  : Undo_Info;
         begin
            if M /= Empty_Move then
               Emit ("move " & To_String (M));
               Make_Move (Pos, M, Undo);
               Record_Current_Key;
               Consume_Move_Count;
            end if;
         end;
      end if;
   end Play_If_My_Turn;

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

   -----------------
   --  UCI go      --
   -----------------

   procedure Handle_UCI_Go (Par : in String) is
      Go : constant UCI.Go_Params := UCI.Parse_Go (Par);
   begin
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

      if not Go.Infinite and then Go.Nodes = 0 and then not UCI_Busy.Busy then
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
                            Go.Nodes, Go.Infinite);
      end;
   end Handle_UCI_Go;

   -------------------
   --  UCI handshake --
   -------------------

   procedure UCI_Handshake is
      Size : constant String :=
        Trim_Both (Natural'Image (Transposition_Size_MB));
   begin
      Emit ("id name BabaChess 1.0");
      Emit ("id author BabaChess");
      Emit ("option name Hash type spin default " & Size
            & " min " & Size & " max " & Size);
      Emit ("option name Threads type spin default 1 min 1 max 16");
      Emit ("option name OwnBook type check default true");
      Emit ("option name BookFile type string default books/book.bin");
      Emit ("option name SyzygyPath type string default <empty>");
      Emit ("uciok");
   end UCI_Handshake;

   -------------------
   --  UCI setoption --
   -------------------

   procedure Handle_UCI_Setoption (Par : in String) is
      use Ada.Characters.Handling;
      Opt : constant UCI.Setoption_Params := UCI.Parse_Setoption (Par);
      Name  : constant String := To_String (Opt.Name);
      Token3 : constant String := To_String (Opt.Token3);
      Value : constant String := To_String (Opt.Value);
   begin
      if UCI_Busy.Busy then
         Emit ("info string setoption ignored while searching");
      elsif Name = "clear" and then Token3 = "hash" then
         Reset_Search;
      elsif Name = "hash" and then Opt.Is_Value then
         if UCI.Parse_Natural (Value, 0) /= Transposition_Size_MB then
            Emit ("info string Hash size is fixed at "
                  & Trim_Both (Natural'Image (Transposition_Size_MB))
                  & " MB (compile-time); clearing table");
         end if;
         Reset_Search;
      elsif Name = "threads" and then Opt.Is_Value then
         Set_Threads (UCI.Parse_Natural (Value, 1));
      elsif Name = "ownbook" and then Opt.Is_Value then
         Own_Book := To_Lower (Value) = "true";
      elsif Name = "bookfile" and then Opt.Is_Value then
         Configure_Book (Value);
      elsif Name = "syzygypath" and then Opt.Is_Value then
         Configure_Syzygy (Value);
      end if;
   end Handle_UCI_Setoption;

   -----------------
   -- XBoard cmds --
   -----------------

   procedure XBoard_Protover is
   begin
      Emit ("feature myname=""BabaChess 1.0""");
      Emit ("feature setboard=1");
      Emit ("feature ping=1");
      Emit ("feature sigint=0 sigterm=0");
      Emit ("feature colors=0 analyze=0");
      Emit ("feature done=1");
   end XBoard_Protover;

   procedure XBoard_New is
   begin
      Pos := Start_Position;
      Engine_Side := Black;
      Force := False;
      Fixed_Time := False;
      Move_Time := 1.0;
      Clock_Left := 0.0;
      Time_Increment := 0.0;
      Moves_To_Go := 0;
      Max_Depth := 64;
      Reset_Search;
      Reset_Game_History;
   end XBoard_New;

   procedure XBoard_Level (Par : in String) is
      Lvl : constant XBoard.Level_Params := XBoard.Parse_Level (Par);
   begin
      Time_Increment := Lvl.Increment_Seconds;
      Moves_Per_Session := Lvl.Moves_Per_Session;
      Moves_To_Go := Moves_Per_Session;
      if not Lvl.Base_Has_Colon then
         Clock_Left := Lvl.Base_Seconds;
      end if;
   end XBoard_Level;

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
            if Cmd = "xboard" then
               Protocol := True;

            elsif Cmd = "uci" then
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

            elsif UCI_Mode
              and then (Cmd = "ponderhit" or else Cmd = "debug"
                        or else Cmd = "register")
            then
               null;

            elsif Cmd = "setoption" and then UCI_Mode then
               Handle_UCI_Setoption (Par);

            elsif Cmd = "protover" then
               XBoard_Protover;

            elsif Cmd = "new" then
               XBoard_New;

            elsif Cmd = "setboard" then
               begin
                  Load (Pos, Par);
                  Force := True;
                  Reset_Game_History;
               exception
                  when Constraint_Error =>
                     Emit ("Error (bad FEN): " & Par);
               end;

            elsif Cmd = "force" then
               Force := True;

            elsif Cmd = "white" then
               Engine_Side := Black;

            elsif Cmd = "black" then
               Engine_Side := White;

            elsif Cmd = "go" then
               Force := False;
               Engine_Side := Pos.Side;
               Play_If_My_Turn;

            elsif Cmd = "level" then
               XBoard_Level (Par);

            elsif Cmd = "time" then
               Clock_Left := XBoard.Parse_Centiseconds (Par);

            elsif Cmd = "otim" then
               null;

            elsif Cmd = "st" then
               begin
                  Move_Time := Duration'Value (Par);
                  Fixed_Time := True;
               exception
                  when Constraint_Error => null;
               end;

            elsif Cmd = "sd" then
               begin
                  Max_Depth := Natural'Value (Par);
               exception
                  when Constraint_Error => null;
               end;

            elsif Cmd = "ping" then
               if Par'Length > 0 then
                  Emit ("pong " & Par);
               else
                  Emit ("pong");
               end if;

            elsif Cmd = "usermove" or else Cmd = "move" then
               declare
                  M    : constant Move_Type := From_String (Pos, Par);
                  Undo : Undo_Info;
               begin
                  if M /= Empty_Move then
                     Make_Move (Pos, M, Undo);
                     Record_Current_Key;
                     Play_If_My_Turn;
                  end if;
               end;

            elsif Cmd = "?" then
               Play_If_My_Turn;

            elsif Cmd = "post" then
               Set_Post (True);

            elsif Cmd = "nopost" then
               Set_Post (False);

            elsif Cmd = "accepted" or else Cmd = "rejected" then
               null;

            elsif Cmd = "easy" or else Cmd = "hard"
              or else Cmd = "hint"
            then
               null;

            elsif Cmd = "quit" or else Cmd = "exit" then
               Quit := True;

            else
               declare
                  M    : constant Move_Type :=
                    From_String (Pos, Trimmed);
                  Undo : Undo_Info;
               begin
                  if M /= Empty_Move then
                     Make_Move (Pos, M, Undo);
                     Record_Current_Key;
                     Play_If_My_Turn;
                  end if;
               end;
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
      Engine_Side := Black;
      Force := True;
      Protocol := False;
      UCI_Mode := False;
      Quit := False;
      Game_N := 0;
      Fixed_Time := False;
      Move_Time := 1.0;
      Clock_Left := 0.0;
      Time_Increment := 0.0;
      Moves_To_Go := 0;
      Moves_Per_Session := 0;
      Max_Depth := 64;
      Own_Book := True;
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

   function Engine_Side_Of return Color_Type is
   begin
      return Engine_Side;
   end Engine_Side_Of;

   function Is_UCI return Boolean is
   begin
      return UCI_Mode;
   end Is_UCI;

   function Busy return Boolean is
   begin
      return UCI_Busy.Busy;
   end Busy;

end BBChess.Protocol;
