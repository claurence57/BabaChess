--
--  BabaChess : principal-variation extraction
--
--  Reads the PV back out of the transposition table: from a position, follow
--  the stored move, verify it is legal, play it, repeat -- stopping on a
--  cycle. Used by the UCI report (one line per iteration, one per MultiPV
--  root move).
--
--  Never raises: an illegal or missing TT move simply ends the line.
--

--  Position and move types are use-visible through the parent's context;
--  Move_List is not declared there, so bring the generator in explicitly.

with BBChess.Movegen;
use BBChess.Movegen;

package BBChess.Search.PV is

   Max_Length : constant := 32;

   procedure Walk (Work      : in out Position_Type;
                   Pv        : out Move_List;
                   Len       : out Natural;
                   Also_Seen : in Bitboard := 0);
   --  Append the line to Pv from index 1 (Len returns the move count),
   --  starting from the position Work (which is left advanced). Stops at the
   --  first missing / empty / illegal entry, at a position already seen on
   --  the line (including Also_Seen when it is not zero) or at Max_Length.

   procedure Extract (Root : in Position_Type;
                      Pv   : out Move_List;
                      Len  : out Natural);
   --  Walk from a by-value copy of Root.

   procedure Extract_Line (Root  : in Position_Type;
                           First : in Move_Type;
                           Pv    : out Move_List;
                           Len   : out Natural);
   --  The PV of one root move: the move itself followed by the continuation
   --  the TT holds after it. The MultiPV report needs it because the root TT
   --  entry only stores the best move.

end BBChess.Search.PV;
