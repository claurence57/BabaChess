--
--  BabaChess : UCI "info" reporting (body)
--

with Ada.Text_IO;

with BBChess.Notation;
use BBChess.Notation;

with BBChess.Movegen;
use BBChess.Movegen;

with BBChess.Search.PV;
with BBChess.Search.TT;
use BBChess.Search.TT;

package body BBChess.Search.Report is

   -- UCI "info" output. Enabled by the "uci" handshake; when on, the primary
   -- thread prints one "info" line per completed iteration with the PV. Off
   -- by default so --selftest and --bench print nothing.
   UCI_Output : Boolean := False;

   procedure Set_Enabled (On : in Boolean) is
   begin
      UCI_Output := On;
   end Set_Enabled;

   function Enabled return Boolean is (UCI_Output);

   -- Single console lock shared by the command loop and the search threads
   -- (Ada.Text_IO is not task-safe). The UCI "info"/"readyok"/"bestmove"
   -- lines all go through it.
   --  A lock, not a protected output action: Ada.Text_IO may block, and a
   --  potentially blocking operation inside a protected action is a bounded
   --  error (RM 9.5.1). Seize/Release the lock around the I/O instead.
   protected Console is
      entry Seize;
      procedure Release;
   private
      Busy : Boolean := False;
   end Console;

   protected body Console is
      entry Seize when not Busy is
      begin
         Busy := True;
      end Seize;

      procedure Release is
      begin
         Busy := False;
      end Release;
   end Console;

   procedure Put_Line (S : in String) is
   begin
      Console.Seize;
      begin
         Ada.Text_IO.Put_Line (S);
         Ada.Text_IO.Flush;
      exception
         when others =>
            --  Never leave the lock held if the I/O raises.
            Console.Release;
            raise;
      end;
      Console.Release;
   end Put_Line;

   procedure Log_Exception
     (Context : in String; Occurrence : in Ada.Exceptions.Exception_Occurrence)
   is
   begin
      --  Same lock as Put_Line (one console lock for the whole engine); the
      --  target is stderr, so the protocol stream is untouched.
      Console.Seize;
      begin
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "warning: " & Context & ": "
            & Ada.Exceptions.Exception_Information (Occurrence));
         Ada.Text_IO.Flush (Ada.Text_IO.Standard_Error);
      exception
         when others =>
            Console.Release;
            raise;
      end;
      Console.Release;
   end Log_Exception;

   procedure Iteration (Root      : in Position_Type;
                        Depth     : in Natural;
                        Sel_Depth : in Natural;
                        Score     : in Score_Type;
                        Elapsed   : in Duration;
                        Nodes     : in Node_Count_Type;
                        Tb_Hits   : in Natural;
                        Best      : in Move_Type;
                        Lines     : in Line_Array)
   is
      Millis : constant Long_Integer :=
        Long_Integer (Elapsed * 1000.0);
      Pv     : Move_List;
      Pv_Len : Natural;
      -- Ample for any value the engine can print (a PV of up to Max_Length
      -- coordinates is ~200 characters).
      Line   : String (1 .. 900);
      Last   : Natural := 0;

      procedure Append (S : in String) is
      begin
         Line (Last + 1 .. Last + S'Length) := S;
         Last := Last + S'Length;
      end Append;

      --  'Image without its leading blank ("5", "-5").
      function Img (X : Score_Type) return String is
         S : constant String := Score_Type'Image (X);
      begin
         return (if S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);
      end Img;

      --  Same for a Natural (the "hashfull" occupancy, per mille).
      function Img_Nat (X : Natural) return String is
         S : constant String := Natural'Image (X);
      begin
         return (if S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);
      end Img_Nat;

      procedure Append_Mate (Positive_Mate : in Boolean; Plies : in Score_Type) is
         M : constant Score_Type :=
           (if Positive_Mate then (Plies + 1) / 2 else Plies / 2);
      begin
         Append (" score mate " & Img (if Positive_Mate then M else -M));
      end Append_Mate;

      --  One UCI "info" line. Multi = 0 is the historical single line (no
      --  "multipv" token, byte-identical output); Multi > 0 adds the index
      --  right after "seldepth", where the UCI specification puts it.
      procedure Emit (Line_Score : in Score_Type;
                      Line_Pv    : in Move_List;
                      Line_Len   : in Natural;
                      Multi      : in Natural) is
      begin
         Last := 0;
         Append ("info depth" & Natural'Image (Depth));
         Append (" seldepth" & Natural'Image (Sel_Depth));
         if Multi > 0 then
            Append (" multipv" & Natural'Image (Multi));
         end if;
         if Line_Score >= Mate_Threshold then
            Append_Mate (True, Mate_Score - Line_Score);
         elsif Line_Score <= -Mate_Threshold then
            Append_Mate (False, Mate_Score + Line_Score);
         else
            Append (" score cp " & Img (Line_Score));
         end if;
         Append (" time" & Long_Integer'Image (Millis));
         Append (" nodes" & Node_Count_Type'Image (Nodes));
         Append (" nps" & Long_Integer'Image
                   (if Millis > 0 then
                      Long_Integer (Nodes) * 1000 / Millis
                    else
                      Long_Integer (Nodes) * 1000));
         Append (" hashfull " & Img_Nat (TT.Hashfull));
         Append (" tbhits" & Natural'Image (Tb_Hits));
         if Line_Len > 0 then
            Append (" pv");
            for I in 1 .. Line_Len loop
               Append (" " & To_String (Line_Pv (I)));
            end loop;
         elsif Best /= Empty_Move then
            -- The TT gave nothing usable: fall back to the iteration's move.
            Append (" pv " & To_String (Best));
         end if;
         Put_Line (Line (1 .. Last));
      end Emit;
   begin
      if not UCI_Output then
         return;
      end if;

      if Lines'Length > 0 then
         --  One line per reported root move, best first (MultiPV). Each
         --  line's PV starts with its own root move; PV.Extract_Line reads
         --  the continuation the TT holds after it.
         for I in Lines'Range loop
            BBChess.Search.PV.Extract_Line (Root, Lines (I).Move, Pv, Pv_Len);
            Emit (Lines (I).Score, Pv, Pv_Len, I - Lines'First + 1);
         end loop;
      else
         -- Extract the PV once (also gives the best move's continuation).
         BBChess.Search.PV.Extract (Root, Pv, Pv_Len);

         -- The first move of the reported PV must be this iteration's best
         -- move: if the TT root entry is stale or replaced (or holds a
         -- different move), fall back to a single-move PV.
         if Best /= Empty_Move
           and then (Pv_Len = 0 or else Pv (1) /= Best)
         then
            Pv (1) := Best;
            Pv_Len := 1;
         end if;

         Emit (Score, Pv, Pv_Len, 0);
      end if;
   end Iteration;

end BBChess.Search.Report;
