--
--  AdaChess-BB : board representation (body)
--

package body BBChess.Board is

   --  GCC builtins imported as compiler intrinsics so they are emitted inline
   --  (POPCNT / BSF) instead of as out-of-line calls into the C shim. Under
   --  the portable build GCC lowers them to libgcc routines, exactly as the C
   --  shim does. This is deliberately a GCC/GNAT dependency, not portable Ada.
   function Intrin_Popcount (X : in Bitboard) return Natural
     with Import, Convention => Intrinsic, External_Name => "__builtin_popcountll";
   function Intrin_Ctz (X : in Bitboard) return Natural
     with Import, Convention => Intrinsic, External_Name => "__builtin_ctzll";

   -----------------
   -- Piece_Board --
   -----------------

   function Piece_Board
     (Position : in Position_Type; Piece : in Piece_Type) return Bitboard is
   begin
      return Position.Board.Pieces (Piece);
   end Piece_Board;

   ------------------
   -- Piece_Boards --
   ------------------

   function Piece_Boards (Position : in Position_Type) return Piece_Board_Array is
   begin
      return Position.Board.Pieces;
   end Piece_Boards;

   ------------------
   -- Color_Boards --
   ------------------

   function Color_Boards (Position : in Position_Type) return Color_Board_Array is
   begin
      return Position.Board.Color_Occ;
   end Color_Boards;

   -----------------
   -- Color_Board --
   -----------------

   function Color_Board (Position : in Position_Type; Color : in Color_Type)
     return Bitboard is
   begin
      return Position.Board.Color_Occ (Color);
   end Color_Board;

   --------------
   -- Occupancy --
   --------------

   function Occupancy (Position : in Position_Type) return Bitboard is
   begin
      return Position.Board.All_Occ;
   end Occupancy;

   --------------
   -- Is_Empty --
   --------------

   function Is_Empty (Position : in Position_Type; Square : in Square_Type)
     return Boolean is
   begin
      return (Occupancy (Position) and Bit (Square)) = 0;
   end Is_Empty;

   --------------
   -- Piece_On --
   --------------

   function Piece_On
     (Position : in Position_Type; Square : in Square_Type) return Piece_Type is
   begin
      return Position.Board.Squares (Square);
   end Piece_On;

   --------------
   -- Piece_At --
   --------------

   function Piece_At
     (Position : in Position_Type;
      Square   : in Square_Type;
      Piece    : out Piece_Type) return Boolean
   is
      Mask : constant Bitboard := Bit (Square);
   begin
      if (Position.Board.All_Occ and Mask) = 0 then
         Piece := White_Pawn;
         return False;
      end if;
      Piece := Position.Board.Squares (Square);
      return True;
   end Piece_At;

   ---------------------
   -- Invariant_Holds --
   ---------------------

   function Invariant_Holds (Position : in Position_Type) return Boolean is
      Expected_All    : Bitboard := 0;
      Expected_Colors : Color_Board_Array := (others => 0);
   begin
      for Piece in Piece_Type loop
         declare
            B     : Bitboard := Position.Board.Pieces (Piece);
            Color : constant Color_Type := Pieces.Color (Piece);
         begin
            --  A square cannot belong to two concrete piece bitboards.
            if (B and Expected_All) /= 0 then
               return False;
            end if;
            Expected_All := Expected_All or B;
            Expected_Colors (Color) := Expected_Colors (Color) or B;

            --  Reading Squares is justified by B, independently of All_Occ:
            --  this also diagnoses a map entry missing on a set piece bit.
            while B /= 0 loop
               declare
                  Square : constant Square_Type := Lowest_Bit (B);
               begin
                  if Position.Board.Squares (Square) /= Piece then
                     return False;
                  end if;
               end;
               B := B and (B - 1);
            end loop;
         end;
      end loop;

      if Expected_All /= Position.Board.All_Occ then
         return False;
      end if;
      for Color in Color_Type loop
         if Expected_Colors (Color) /= Position.Board.Color_Occ (Color) then
            return False;
         end if;
      end loop;

      return
        (Position.Board.Color_Occ (White) and Position.Board.Color_Occ (Black)) = 0
        and then (Position.Board.Color_Occ (White)
                  or Position.Board.Color_Occ (Black)) = Position.Board.All_Occ;
   end Invariant_Holds;

   --------------
   -- Put_Piece --
   --------------

   procedure Put_Piece
     (Position : in out Position_Type; Piece : in Piece_Type; Square : in Square_Type)
   is
      M : constant Bitboard := Bit (Square);
   begin
      Position.Board.Pieces (Piece) := Position.Board.Pieces (Piece) or M;
      Position.Board.All_Occ := Position.Board.All_Occ or M;
      Position.Board.Color_Occ (Pieces.Color (Piece)) :=
        Position.Board.Color_Occ (Pieces.Color (Piece)) or M;
      Position.Board.Squares (Square) := Piece;
   end Put_Piece;

   -----------------
   -- Remove_Piece --
   -----------------

   procedure Remove_Piece
     (Position : in out Position_Type; Piece : in Piece_Type; Square : in Square_Type)
   is
      M : constant Bitboard := not Bit (Square);
   begin
      Position.Board.Pieces (Piece) := Position.Board.Pieces (Piece) and M;
      Position.Board.All_Occ := Position.Board.All_Occ and M;
      Position.Board.Color_Occ (Pieces.Color (Piece)) :=
        Position.Board.Color_Occ (Pieces.Color (Piece)) and M;
   end Remove_Piece;

   ----------------
   -- Move_Piece --
   ----------------

   procedure Move_Piece
     (Position : in out Position_Type; Piece : in Piece_Type;
      From, To : in Square_Type)
   is
      Flip : constant Bitboard := Bit (From) xor Bit (To);
      Col  : constant Color_Type := Pieces.Color (Piece);
   begin
      Position.Board.Pieces (Piece) := Position.Board.Pieces (Piece) xor Flip;
      Position.Board.All_Occ := Position.Board.All_Occ xor Flip;
      Position.Board.Color_Occ (Col) := Position.Board.Color_Occ (Col) xor Flip;
      Position.Board.Squares (To) := Piece;
   end Move_Piece;

   ---------------
   -- Lowest_Bit --
   ---------------

   function Lowest_Bit (Board : in Bitboard) return Square_Type is
   begin
      return Square_Type (Intrin_Ctz (Board));
   end Lowest_Bit;

   -------------
   -- Popcount --
   -------------

   function Popcount (Board : in Bitboard) return Natural is
   begin
      return Intrin_Popcount (Board);
   end Popcount;

end BBChess.Board;
