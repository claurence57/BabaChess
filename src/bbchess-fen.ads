--
--  AdaChess-BB : FEN loading
--
--  Minimal FEN parser used to set a Position from its Forsyth-Edwards
--  notation. Enough for the perft suite and later for the XBoard "setboard"
--  command.
--

with BBChess.Board;
use BBChess.Board;

package BBChess.Fen is

   procedure Load (Position : out Position_Type; Text : in String);
   -- Parse a FEN string into Position. Raises Constraint_Error on garbage
   -- and on illegal positions: the board must contain exactly one king per
   -- side and the side that does not have the move must not be in check.

   function To_String (Position : in Position_Type) return String;
   -- Six-field FEN of Position, the inverse of Load: castling rights and the
   -- en-passant square come from the record, the halfmove and fullmove clocks
   -- from their fields. Load (To_String (P)) reproduces P.

end BBChess.Fen;
