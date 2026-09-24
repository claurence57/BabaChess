--
--  AdaChess-BB : attack tables
--
--  Precomputed attack sets:
--    * Knight_Attacks / King_Attacks / Pawn_Attacks : leapers, table lookups.
--    * Bishop_Attacks / Rook_Attacks : PEXT (BMI2) lookup (one indexed
--      table read); a software fallback is used in the portable build.
--    * Queen_Attacks = Rook_Attacks or Bishop_Attacks.
--
--  All tables are built once at elaboration (deterministic seed). The
--  caller only provides an occupancy bitboard (any subset of the 64 squares).
--
--  The tables themselves are held in the private part and reached through
--  Inline accessors, so nothing outside this package can corrupt them after
--  Init. At -O3 the accessors compile to the same indexed table read the
--  former public variables produced (checked: --bench node counts and nps
--  unchanged).
--

with BBChess.Pieces;
use BBChess.Pieces;

with BBChess.Board;
use BBChess.Board;

package BBChess.Attacks is

   pragma Elaborate_Body (BBChess.Attacks);

   -- Leaper attacks, indexed by the origin square.
   function Knight_Attacks (Square : in Square_Type) return Bitboard
     with Inline;
   function King_Attacks (Square : in Square_Type) return Bitboard
     with Inline;
   function Pawn_Attacks (Color : in Color_Type; Square : in Square_Type)
     return Bitboard with Inline;

   -- Sliding attacks (consider the given occupancy).
   function Bishop_Attacks (Square : in Square_Type; Occupancy : in Bitboard)
     return Bitboard with Inline;
   function Rook_Attacks (Square : in Square_Type; Occupancy : in Bitboard)
     return Bitboard with Inline;
   function Queen_Attacks (Square : in Square_Type; Occupancy : in Bitboard)
     return Bitboard with Inline;

   -- Square-to-square tables (empty when the two squares are not aligned).
   --   Between (A, B) : squares strictly between A and B.
   --   Line (A, B)    : the whole line through A and B, A and B included.
   -- Used by check evasion and pin handling.
   function Between (A, B : in Square_Type) return Bitboard with Inline;
   function Line    (A, B : in Square_Type) return Bitboard with Inline;

   -- Full sliding rays (empty board): Rook_Attacks (S, 0) and
   -- Bishop_Attacks (S, 0). Precomputed so Pin_Mask does not have to run
   -- PEXT with a zero occupancy on every call.
   function Rook_Ray   (Square : in Square_Type) return Bitboard with Inline;
   function Bishop_Ray (Square : in Square_Type) return Bitboard with Inline;

   -- Whole file bitboards (used for bulk pawn move generation).
   function File_A_BB return Bitboard with Inline;
   function File_H_BB return Bitboard with Inline;

private

   -- Maximum index used by the PEXT sliding lookup (rook relevant bits <= 12,
   -- bishop relevant bits <= 9).
   Max_Rook_Index   : constant := 4095;
   Max_Bishop_Index : constant := 511;

   type Rook_Attack_Table_Type is
     array (Square_Type, Natural range 0 .. Max_Rook_Index) of Bitboard;
   Rook_Attack_Table : Rook_Attack_Table_Type := (others => (others => 0));

   type Bishop_Attack_Table_Type is
     array (Square_Type, Natural range 0 .. Max_Bishop_Index) of Bitboard;
   Bishop_Attack_Table : Bishop_Attack_Table_Type := (others => (others => 0));

   -- Relevant-occupancy masks for the PEXT-based sliding lookup.
   Rook_Mask   : array (Square_Type) of Bitboard := (others => 0);
   Bishop_Mask : array (Square_Type) of Bitboard := (others => 0);

   -- Leaper tables (private: read through the accessors above).
   Knight_Table : array (Square_Type) of Bitboard := (others => 0);
   King_Table   : array (Square_Type) of Bitboard := (others => 0);
   Pawn_Table   : array (Color_Type, Square_Type) of Bitboard :=
     (others => (others => 0));

   -- Square-to-square tables and full rays.
   Between_Table : array (Square_Type, Square_Type) of Bitboard :=
     (others => (others => 0));
   Line_Table    : array (Square_Type, Square_Type) of Bitboard :=
     (others => (others => 0));
   Rook_Ray_Table   : array (Square_Type) of Bitboard := (others => 0);
   Bishop_Ray_Table : array (Square_Type) of Bitboard := (others => 0);

   File_A_Table : Bitboard := 0;
   File_H_Table : Bitboard := 0;

end BBChess.Attacks;
