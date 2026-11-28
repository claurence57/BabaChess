--
--  AdaChess-BB : board representation
--
--  Bitboard basics:
--    * Square_Type : Natural range 0 .. 63.
--    * A square index is computed as Rank * 8 + File, with Rank 0 = rank 1
--      (the white home rank) and File 0 = file A. Hence bit 0 = a1 and
--      bit 63 = h8. Increasing index = "north" is +8 (toward black).
--    * Bitboard : modular 64-bit type. Sets/unions/intersections are done
--      with the usual "or", "and", "not" operators on modular types.
--
--  A Position keeps the pieces as 12 separate bitboards plus the side to
--  move. Total and per-colour occupancies, and the square-to-piece map, are
--  maintained incrementally with the piece bitboards. Those four coupled
--  components live in a private Board_State so clients cannot update only one
--  of them; reads remain inlineable.
--

with BBChess.Pieces;
use BBChess.Pieces;

package BBChess.Board is

   subtype Square_Type is Natural range 0 .. 63;

   type Bitboard is mod 2 ** 64;

   function File_Of (Square : in Square_Type) return Natural is (Square mod 8);
   function Rank_Of (Square : in Square_Type) return Natural is (Square / 8);

   pragma Inline (File_Of);
   pragma Inline (Rank_Of);

   --  Static, read-only mask with exactly one bit set for each square. An
   --  aggregate avoids elaboration code and any package-elaboration ordering.
   type Bit_Table_Type is array (Square_Type) of Bitboard;
   Bit : constant Bit_Table_Type :=
     (0 => 16#0000000000000001#, 1 => 16#0000000000000002#,
      2 => 16#0000000000000004#, 3 => 16#0000000000000008#,
      4 => 16#0000000000000010#, 5 => 16#0000000000000020#,
      6 => 16#0000000000000040#, 7 => 16#0000000000000080#,
      8 => 16#0000000000000100#, 9 => 16#0000000000000200#,
      10 => 16#0000000000000400#, 11 => 16#0000000000000800#,
      12 => 16#0000000000001000#, 13 => 16#0000000000002000#,
      14 => 16#0000000000004000#, 15 => 16#0000000000008000#,
      16 => 16#0000000000010000#, 17 => 16#0000000000020000#,
      18 => 16#0000000000040000#, 19 => 16#0000000000080000#,
      20 => 16#0000000000100000#, 21 => 16#0000000000200000#,
      22 => 16#0000000000400000#, 23 => 16#0000000000800000#,
      24 => 16#0000000001000000#, 25 => 16#0000000002000000#,
      26 => 16#0000000004000000#, 27 => 16#0000000008000000#,
      28 => 16#0000000010000000#, 29 => 16#0000000020000000#,
      30 => 16#0000000040000000#, 31 => 16#0000000080000000#,
      32 => 16#0000000100000000#, 33 => 16#0000000200000000#,
      34 => 16#0000000400000000#, 35 => 16#0000000800000000#,
      36 => 16#0000001000000000#, 37 => 16#0000002000000000#,
      38 => 16#0000004000000000#, 39 => 16#0000008000000000#,
      40 => 16#0000010000000000#, 41 => 16#0000020000000000#,
      42 => 16#0000040000000000#, 43 => 16#0000080000000000#,
      44 => 16#0000100000000000#, 45 => 16#0000200000000000#,
      46 => 16#0000400000000000#, 47 => 16#0000800000000000#,
      48 => 16#0001000000000000#, 49 => 16#0002000000000000#,
      50 => 16#0004000000000000#, 51 => 16#0008000000000000#,
      52 => 16#0010000000000000#, 53 => 16#0020000000000000#,
      54 => 16#0040000000000000#, 55 => 16#0080000000000000#,
      56 => 16#0100000000000000#, 57 => 16#0200000000000000#,
      58 => 16#0400000000000000#, 59 => 16#0800000000000000#,
      60 => 16#1000000000000000#, 61 => 16#2000000000000000#,
      62 => 16#4000000000000000#, 63 => 16#8000000000000000#);

   --  A distinct bounded type admits either no square or a real board square.
   --  Keeping Ep_None outside Square_Type preserves the existing layout and
   --  semantics while rejecting every other invalid integer.
   type En_Passant_Type is new Integer range -1 .. 63;
   Ep_None : constant En_Passant_Type := -1;

   type Castle_Side_Type is (King_Side, Queen_Side);
   type Castle_Rights_Type is array (Color_Type, Castle_Side_Type) of Boolean;

   type Piece_Board_Array is array (Piece_Type) of Bitboard;
   type Color_Board_Array is array (Color_Type) of Bitboard;

   --  Only this coupled board state is private. Clocks, rights, key and other
   --  independent game-state fields remain directly accessible: wrapping them
   --  would enlarge the patch without strengthening the board invariant.
   type Board_State is private;

   type Position_Type is
      record
         Board       : Board_State;
         Side        : Color_Type := White;
         Castle      : Castle_Rights_Type := (others => (others => False));
         En_Passant  : En_Passant_Type := Ep_None;
         Halfmove    : Natural := 0;
         Fullmove    : Positive := 1;
         Key         : Bitboard := 0;
         Material    : Integer := 0;   -- White-positive material + PST
      end record;

   function Piece_Board
     (Position : in Position_Type; Piece : in Piece_Type) return Bitboard;
   --  Read-only view of one piece bitboard.

   function Piece_Boards (Position : in Position_Type) return Piece_Board_Array;
   function Color_Boards (Position : in Position_Type) return Color_Board_Array;
   --  Snapshots by value for algorithms such as SEE that mutate a compact,
   --  private working copy. Changing a snapshot cannot corrupt Position.

   function Color_Board (Position : in Position_Type; Color : in Color_Type)
     return Bitboard;
   --  Incrementally maintained union of the six piece boards of Color.

   function Occupancy (Position : in Position_Type) return Bitboard;
   --  Incrementally maintained union of every piece board.

   function Is_Empty (Position : in Position_Type; Square : in Square_Type)
     return Boolean;
   --  True when no piece stands on Square.

   function Piece_On
     (Position : in Position_Type; Square : in Square_Type) return Piece_Type
     with Pre => not Is_Empty (Position, Square);
   --  Piece on a square already known to be occupied. Unlike Piece_At, this
   --  hot-path accessor does not repeat the occupancy test.

   function Piece_At
     (Position : in Position_Type;
      Square   : in Square_Type;
      Piece    : out Piece_Type) return Boolean;
   --  Look up the piece standing on Square. Returns True (and fills Piece)
   --  when Square is occupied, False when it is empty.

   function Invariant_Holds (Position : in Position_Type) return Boolean;
   --  Full consistency check: no duplicate piece bits, exact piece/occupancy
   --  unions and a square map matching every occupied piece bit. Deliberately
   --  not on hot paths; intended for tests and diagnostics.

   procedure Put_Piece
     (Position : in out Position_Type; Piece : in Piece_Type; Square : in Square_Type)
     with Pre  => Is_Empty (Position, Square),
          Post => not Is_Empty (Position, Square)
                  and then Piece_On (Position, Square) = Piece
                  and then (Piece_Board (Position, Piece) and Bit (Square)) /= 0
                  and then (Color_Board (Position, Pieces.Color (Piece))
                            and Bit (Square)) /= 0;
   --  Place a piece on an empty Square and update every board view.

   procedure Remove_Piece
     (Position : in out Position_Type; Piece : in Piece_Type; Square : in Square_Type)
     with Pre  => not Is_Empty (Position, Square)
                  and then Piece_On (Position, Square) = Piece
                  and then (Piece_Board (Position, Piece) and Bit (Square)) /= 0,
          Post => Is_Empty (Position, Square)
                  and then (Piece_Board (Position, Piece) and Bit (Square)) = 0
                  and then (Color_Board (Position, Pieces.Color (Piece))
                            and Bit (Square)) = 0;
   --  Remove exactly Piece from Square and update every board view. The stale
   --  square-map entry remains deliberately unreadable while Square is empty.

   procedure Move_Piece
     (Position : in out Position_Type; Piece : in Piece_Type;
      From, To : in Square_Type)
     with Pre  => From /= To
                  and then not Is_Empty (Position, From)
                  and then Piece_On (Position, From) = Piece
                  and then (Piece_Board (Position, Piece) and Bit (From)) /= 0
                  and then Is_Empty (Position, To),
          Post => Is_Empty (Position, From)
                  and then not Is_Empty (Position, To)
                  and then Piece_On (Position, To) = Piece
                  and then (Piece_Board (Position, Piece) and Bit (From)) = 0
                  and then (Piece_Board (Position, Piece) and Bit (To)) /= 0;
   --  Relocate Piece from an occupied From to an empty, distinct To in one
   --  pass. The piece/occupancy/colour bitboards are each toggled by
   --  (Bit (From) or Bit (To)) -- three XORs instead of a Remove_Piece +
   --  Put_Piece pair (six and/or operations). Same result.

   function Lowest_Bit (Board : in Bitboard) return Square_Type
     with Pre => Board /= 0;
   --  Index of the least significant set bit. The GCC intrinsic is undefined
   --  for zero, so this public precondition is part of the API.

   function Popcount (Board : in Bitboard) return Natural;
   --  Number of set bits (population count).

   --  Hot cross-unit primitives: inlined into callers under -gnatN.
   pragma Inline (Piece_Board);
   pragma Inline (Piece_Boards);
   pragma Inline (Color_Boards);
   pragma Inline (Piece_At);
   pragma Inline (Color_Board);
   pragma Inline (Occupancy);
   pragma Inline (Is_Empty);
#if ASSERTS then
   --  GNAT does not enforce Pre/Post on subprograms inlined at -O3. Keep the
   --  checked/debug builds honest; release retains the zero-cost hot path.
   pragma No_Inline (Piece_On);
   pragma No_Inline (Lowest_Bit);
   pragma No_Inline (Put_Piece);
   pragma No_Inline (Remove_Piece);
   pragma No_Inline (Move_Piece);
#else
   pragma Inline (Piece_On);
   pragma Inline (Lowest_Bit);
   pragma Inline (Put_Piece);
   pragma Inline (Remove_Piece);
   pragma Inline (Move_Piece);
#end if;
   pragma Inline (Popcount);

private

   --  Squares (S) is meaningful only while S is in All_Occ. There is no empty
   --  value in Piece_Type, so removal leaves a stale value behind. Piece_At
   --  checks occupancy before reading it; Piece_On carries the same contract.
   type Square_Piece_Array is array (Square_Type) of Piece_Type;

   type Board_State is
      record
         Pieces    : Piece_Board_Array := (others => 0);
         All_Occ   : Bitboard := 0;
         Color_Occ : Color_Board_Array := (others => 0);
         Squares   : Square_Piece_Array := (others => White_Pawn);
      end record;

end BBChess.Board;
