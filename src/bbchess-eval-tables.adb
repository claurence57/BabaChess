--
--  BabaChess : evaluation data (body)
--
--  The tuning procedures and the material+PST rebuild. Nothing here is on
--  the evaluation's hot path: it runs at start-up, when a parameter file is
--  loaded, or when the tuner overrides one value.
--

with Ada.Characters.Handling;

with BBChess.Tunable;

package body BBChess.Eval.Tables is

   function Piece_Value (Kind : in Kind_Type) return Score_Type is
   begin
      case Kind is
         when Pawn   => return Score_Type (Params (P_Pawn));
         when Knight => return Score_Type (Params (P_Knight));
         when Bishop => return Score_Type (Params (P_Bishop));
         when Rook   => return Score_Type (Params (P_Rook));
         when Queen  => return Score_Type (Params (P_Queen));
         when King   => return 0;
      end case;
   end Piece_Value;

   function PST (Kind : in Kind_Type; Color : in Color_Type;
                 Square : in Square_Type) return Score_Type is
      File_Idx : constant Natural := File_Of (Square);
      Row      : Natural;
   begin
      if Color = White then
         Row := Rank_Of (Square);
      else
         Row := 7 - Rank_Of (Square);
      end if;

      case Kind is
         when Pawn   => return Pawn_PST (Row, File_Idx);
         when Knight => return Knight_PST (Row, File_Idx);
         when Bishop => return Bishop_PST (Row, File_Idx);
         when Rook   => return Rook_PST (Row, File_Idx);
         when Queen  => return Queen_PST (Row, File_Idx);
         when King   => return King_PST (Row, File_Idx);
      end case;
   end PST;

   -- Rebuild the flat material+PST table after a piece value changed.
   procedure Rebuild_Material_PST is
   begin
      for P in Piece_Type loop
         for S in Square_Type loop
            Material_PST (P, S) :=
              Piece_Value (Kind (P)) + PST (Kind (P), Color (P), S);
         end loop;
      end loop;
   end Rebuild_Material_PST;

   procedure Set_Param (Name : in String; Value : in Integer) is
      use Ada.Characters.Handling;
      U : constant String := To_Upper (Name);
   begin
      for Id in Param_Id loop
         if U = Param_Id'Image (Id) then
            Params (Id) := Value;
            if Id in P_Pawn | P_Knight | P_Bishop | P_Rook | P_Queen then
               Rebuild_Material_PST;
            end if;
            return;
         end if;
      end loop;

      -- Table entries (tuner names, see Dump_Params):
      --   P_PST_<T>_<row>_<file>  T in P N B R Q K KE, file 0 .. 3; the
      --                           mirrored file 7 - file gets the same value;
      --   P_PASSED_OP_<row> / P_PASSED_EG_<row>.
      if U'Length = 13 and then U (U'First .. U'First + 11) = "P_PASSED_OP_"
        and then U (U'Last) in '0' .. '7'
      then
         Passed_Pawn_Opening (Character'Pos (U (U'Last)) - Character'Pos ('0'))
           := Value;
         return;
      end if;
      if U'Length = 13 and then U (U'First .. U'First + 11) = "P_PASSED_EG_"
        and then U (U'Last) in '0' .. '7'
      then
         Passed_Pawn_Endgame (Character'Pos (U (U'Last)) - Character'Pos ('0'))
           := Value;
         return;
      end if;
      if U'Length >= 11 and then U (U'First .. U'First + 5) = "P_PST_"
        and then U (U'Last) in '0' .. '3'
        and then U (U'Last - 1) = '_'
        and then U (U'Last - 2) in '0' .. '7'
        and then U (U'Last - 3) = '_'
      then
         declare
            T   : constant String := U (U'First + 6 .. U'Last - 4);
            Row : constant Natural :=
              Character'Pos (U (U'Last - 2)) - Character'Pos ('0');
            Fl  : constant Natural :=
              Character'Pos (U (U'Last)) - Character'Pos ('0');
            procedure Put_Entry (Tbl : in out PST_Table) is
            begin
               Tbl (Row, Fl) := Value;
               Tbl (Row, 7 - Fl) := Value;
            end Put_Entry;
         begin
            if T = "P" then
               Put_Entry (Pawn_PST);
            elsif T = "N" then
               Put_Entry (Knight_PST);
            elsif T = "B" then
               Put_Entry (Bishop_PST);
            elsif T = "R" then
               Put_Entry (Rook_PST);
            elsif T = "Q" then
               Put_Entry (Queen_PST);
            elsif T = "K" then
               Put_Entry (King_PST);
            elsif T = "KE" then
               Put_Entry (King_End_PST);
            else
               return;
            end if;
            Rebuild_Material_PST;
         end;
      end if;
   end Set_Param;

   -- Real parameters do not exist on the evaluation side: the shared file
   -- loader offers a fractional token here, and it is ignored exactly as the
   -- historical Constraint_Error guard did.
   procedure Set_Real_Param (Name : in String; Value : in Float) is
      pragma Unreferenced (Name, Value);
   begin
      null;
   end Set_Real_Param;

   procedure Load_Params_File is new BBChess.Tunable.Load_File
     (Set_Integer => Set_Param,
      Set_Real    => Set_Real_Param);

   procedure Load_Params (File_Name : in String) is
   begin
      Load_Params_File (File_Name);
      Rebuild_Material_PST;
   end Load_Params;

   function Image_Digit (N : in Natural) return String is
     ((1 => Character'Val (Character'Pos ('0') + N)));

   -- Dump the queen-side half (files 0 .. 3) of a PST; Set_Param mirrors it.
   procedure Dump_PST (T : in String; Tbl : in PST_Table;
                       First_Row, Last_Row : in Natural) is
   begin
      for R in First_Row .. Last_Row loop
         for F in 0 .. 3 loop
            BBChess.Tunable.Put ("P_PST_" & T & "_" & Image_Digit (R) & "_"
                                 & Image_Digit (F), Tbl (R, F));
         end loop;
      end loop;
   end Dump_PST;

   procedure Dump_Params is
   begin
      for Id in Param_Id loop
         BBChess.Tunable.Put (Param_Id'Image (Id), Params (Id));
      end loop;
      for R in 1 .. 6 loop
         BBChess.Tunable.Put ("P_PASSED_OP_" & Image_Digit (R),
                              Passed_Pawn_Opening (R));
         BBChess.Tunable.Put ("P_PASSED_EG_" & Image_Digit (R),
                              Passed_Pawn_Endgame (R));
      end loop;
      Dump_PST ("P", Pawn_PST, 1, 6);
      Dump_PST ("N", Knight_PST, 0, 7);
      Dump_PST ("B", Bishop_PST, 0, 7);
      Dump_PST ("R", Rook_PST, 0, 7);
      Dump_PST ("Q", Queen_PST, 0, 7);
      Dump_PST ("K", King_PST, 0, 7);
      Dump_PST ("KE", King_End_PST, 0, 7);
   end Dump_Params;

begin
   -- Precompute the flat material+PST table.
   Rebuild_Material_PST;

end BBChess.Eval.Tables;
