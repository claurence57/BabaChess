--
--  AdaChess-BB : static exchange evaluation (SEE)
--
--  Estimates the material outcome of a capture sequence on a single square,
--  assuming both sides answer with their cheapest available attacker. The
--  value is used to avoid searching losing captures (SEE < 0) in the
--  quiescence search.
--
--  Model (shared with the mailbox engine for reference):
--    * both sides recapture only on the destination square, choosing their
--      least valuable attacker first (pinned pieces cannot take part);
--    * a recapture may be declined (standing pat at 0), so a losing line is
--      simply dropped;
--    * a king may be the last attacker only - the exchange stops right after
--      a king capture.
--
--  Sliding x-ray attackers are naturally revealed because the occupancy is
--  updated at every step of the sequence.

with BBChess.Board;
use BBChess.Board;

with BBChess.Moves;
use BBChess.Moves;

with BBChess.Eval;
use BBChess.Eval;

package BBChess.See is

   function Static_Exchange_Value
     (Position : in Position_Type;
      Move     : in Move_Type) return Score_Type
   with
     Pre =>
       --  The move must be well-formed against the position: distinct origin
       --  and destination, and (for anything but a promotion, which may be
       --  evaluated before the piece is on the board) the moving piece
       --  actually stands on the origin square. The side to move is not
       --  required to match the move's colour: SEE is a static property of
       --  the exchange.
       Move.From /= Move.To
       and then (Move.Flag = Promotion
                 or else (Position.Pieces (Move.Piece) and Bit (Move.From)) /= 0);
   -- Net centipawn outcome, from the point of view of the side to move, of
   -- playing Move (a capture, an en-passant or a promotion). Positive means
   -- the exchange wins material, negative that it loses some. Non-tactical
   -- moves return 0.

end BBChess.See;
