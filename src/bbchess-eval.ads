--
--  AdaChess-BB : static evaluation
--
--  Material + piece-square tables, tapered by the game phase (opening /
--  endgame interpolation) and completed by positional terms: bishop pair,
--  piece mobility, rooks on the 7th rank, passed pawns, king safety and
--  king endgame activity. Scores are in centipawns, positive from White's
--  point of view. Every term is evaluated per color and mirrored, so the
--  evaluation is symmetric and returns 0 on the initial position.
--

with BBChess.Pieces;
use BBChess.Pieces;

with BBChess.Board;
use BBChess.Board;

package BBChess.Eval is

   subtype Score_Type is Integer;
   -- Pseudo-infinite bounds for the search.
   Infinity   : constant Score_Type := 30_000;
   Mate_Score : constant Score_Type := 30_000;

   -- Tempo bonus granted to the side to move (added by Evaluate).
   Tempo : constant Score_Type := 10;

   function Static (Position : in Position_Type) return Score_Type;
   -- Material + position, positive when White is better. Fully symmetric:
   -- Static(M) = -Static(P) when M mirrors P (rank flip + color swap).

   --  The named terms Static sums. A "why does this position score X" question
   --  decomposes into exactly these entries.
   type Eval_Term is
     (Material_Term,
      Bishop_Pair,
      Mobility,
      Connected_Rooks,
      Pawn_Structure,
      Pawn_Threats,
      Outpost,
      King_Activity,
      King_Safety,
      Hanging,
      Drawish_Scale,
      Minor_Imbalance);

   type Eval_Breakdown is array (Eval_Term) of Integer;

   function Game_Phase (Position : in Position_Type) return Natural;
   -- Phase from the remaining material: 100 = full opening, 0 = pure endgame.

   function Breakdown (Position : in Position_Type;
                       Terms    : out Eval_Breakdown) return Score_Type;
   -- Same value as Static, plus each named term's white-positive contribution
   -- blended at the current phase (centipawns). Each term is blended on its
   -- own, so the rounded contributions can differ from the total by a
   -- centipawn or two (the engine blends the tapered sum once).

   function Evaluate (Position : in Position_Type) return Score_Type;
   -- Static evaluation from the point of view of the side to move
   -- (convenient for a negamax framework), plus the Tempo bonus for the
   -- side to move. Note: because of the tempo, Evaluate is *not* exactly
   -- antisymmetric under a rank flip + color swap that keeps the same side
   -- to move; the pure antisymmetry holds on Static.

   function Material_PST_Value (Piece  : in Piece_Type;
                                Square : in Square_Type) return Integer;
   -- Material + piece-square value of one piece (from White's point of
   -- view). Used by Make_Move to keep Position.Material up to date.
   pragma Inline (Material_PST_Value);

   function Compute_Material (Position : in Position_Type) return Integer;
   -- Full recompute of the White-positive material + PST total. Used to
   -- initialize Position.Material after Load / Start_Position and by the
   -- self test that checks the incremental update.

   -- Automatic tuning interface: the scalar evaluation constants are held in
   -- a table and can be overridden by name (e.g. "P_Mobility_N 5").
   procedure Set_Param (Name : in String; Value : in Integer);
   procedure Load_Params (File_Name : in String);
   procedure Dump_Params;

end BBChess.Eval;
