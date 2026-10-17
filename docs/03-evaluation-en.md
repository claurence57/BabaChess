# 3. Evaluation

Evaluation scores a frozen position, without anticipating any moves: "who is
better, and by how much?". The search calls it at every leaf, so its quality
steers the whole game. This chapter starts from material and adds the ingredients
of the positional: scale, values, piece-square tables, phase, terms, drawishness
scaling, symmetry, lazy evaluation and automatic tuning. BabaChess, a bitboard
engine in Ada 2012, is the example: handcrafted evaluation, no NNUE, tuned by
Texel.

## 3.1 From material to positional

The simplest evaluation adds up the value of each side's pieces and subtracts:
the difference is the score. That already beats a beginner. But with equal
material, a central knight is worth more than a knight on the edge, connected
pawns more than doubled pawns, a sheltered king more than an exposed one. A
positional evaluation therefore adds **terms** to the material sum (mobility, pawn
structure, king safety...), each capturing a piece of chess knowledge.

## 3.2 The centipawn scale

A score is measured in **centipawns**: a pawn is worth 100. The sign is
conventional, positive when White is better; +50 announces a half-pawn advantage.
The mate bounds (`Infinity`, `Mate_Score`, `30_000` in BabaChess) bracket the
ordinary values: the search can thus tell a mate from a merely winning position.

## 3.3 Piece values

The classic table is the foundation: pawn 100, knight 320, bishop 330, rook 500,
queen 900, king 0. The bishop is worth slightly more than the knight, the rook a
little under five pawns. The king is worth zero because it cannot be captured;
its value plays out in safety. These numbers are conventions that automatic
tuning adjusts.

## 3.4 Piece-square tables

A **piece-square table** (PST) is an 8×8 array giving, per piece and per square, a
bonus or a penalty: a knight penalised on the edges, a bishop drawn to the long
diagonals, a rook rewarded on the 7th, a king pushed to the centre in the
endgame. Written from one side's point of view, rows running from the back rank
(0) to the enemy side (7), it is read as `Rank_Of (square)` for White and
`7 - Rank_Of (square)` for Black: a **single table serves both sides**, with no
duplication. BabaChess names them `Pawn_PST`, `Knight_PST`, `Bishop_PST`,
`Rook_PST`, `Queen_PST`, `King_PST` and `King_End_PST`.

## 3.5 Game phase and tapered evaluation

Not all terms weigh the same depending on how far the game has advanced: a rook
on an open file is useful in the middlegame and decisive in the endgame, a central
king is dangerous there then excellent. **Tapered evaluation** therefore scores
each term **twice**, opening and endgame, then **interpolates** according to the
phase. The phase comes from the remaining material (4 per knight, 4 per bishop, 9
per rook, 16 per queen, capped at 100): 100 at the start, 0 in a kings-and-pawns
endgame.

BabaChess carries the `Opening` / `End_Game` pair in a `Tapered_Score_Type` and
interpolates it with `Blend`: bishop pair from 20 to 45, rook on the 7th from 15
to 35, passed pawns with a bonus growing with the rank, `King_End_PST` correcting
the king in the endgame.

## 3.6 The positional terms

Each term is computed **per colour**, then the two scores are subtracted. Writing
the code with a generic colour, without "White" / "Black" branches, is the key to
symmetry (section 3.8).

### 3.6.1 Pawn structure

It is detected on bitboards, with no loop over pawns:

- **doubled**: more than one pawn on a file, a penalty per extra pawn;
- **isolated**: no friendly pawn on the neighbouring files, a penalty per pawn;
- **passed**: no enemy pawn ahead, a bonus that grows with the rank;
- **backward**: a delayed pawn, often on a semi-open file.

BabaChess detects passed pawns with `Front_Blockers`: widened files, rank-by-rank
propagation, seven fixed shifts.

### 3.6.2 Pieces: mobility, bishop pair, rooks, threats

**Mobility** counts the reachable squares: for each knight, bishop, rook and
queen, the attacks are generated according to the occupancy and the free squares
are counted, `Popcount (Piece_Attacks and Free)`. The weight depends on the piece,
the knight and bishop being the most sensitive to their freedom. The **bishop
pair** adds a bonus, stronger in the endgame. **Rooks** like the 7th rank
(reinforced if the enemy king stayed back), open files (no pawn) or semi-open
files (no friendly pawn), and connect when they defend each other on the same
line. **Threats** reward attacks on undefended pieces: an enemy piece attacked by
a friendly pawn, or a knight / bishop attacking a rook or queen. File masks
(`File_Mask`) avoid any loop over pawns; BabaChess computes the attack set once
per evaluation.

### 3.6.3 King safety

King safety locates the attackers around the king and the weaknesses of its
shelter: pawn shield, open files, enemy advance (pawn storm). The danger is
**non-linear**, a coordinated attack weighing more than the sum of the pieces. It
is the most delicate term: BabaChess limits it to the opening and middlegame
(`Phase >= King_Safety_Min_Phase`) and keeps it frozen.

## 3.7 Drawishness scaling

A position winning on paper can be drawn in practice: a piece up with no pawn, or
opposite-coloured bishops. Keeping the whole material bonus there pushes the
search to fight for a gain that does not exist. **Drawishness scaling** then
multiplies the score by a factor below one. BabaChess computes a `Scale_Factor`
out of 64: with no pawn and at most one minor piece ahead, 0, 4 or 14; only
opposite-coloured bishops, `Scale_OCB`.

## 3.8 Evaluation symmetry

Evaluation must be **symmetric**: flipping the board while swapping the colours
must change the sign of the score, otherwise a bias would favour one side. Three
rules watch over it: PSTs read the rank in the colour's own frame; terms are
computed with a generic colour and then subtracted; `Static` adds nothing that
depends on the side to move. The property is written `Static (M) = -Static (P)`
when `M` mirrors `P`. Because `Evaluate` adds a **tempo bonus**, the exact
symmetry holds on `Static`. It is tested through invariants (`Static` of the start
= 0, `Evaluate` = tempo, mirror opposite), which `Check_Symmetry` does on varied
FEN. Any new evaluation must stay symmetric: it is the golden rule.

## 3.9 Lazy evaluation

Computing every term at each leaf is expensive. **Lazy evaluation** exploits
reasoning in bounds: if the material-plus-tables total already exceeds the current
bound by a sufficient margin, the detail does not change the decision and that
approximate total is returned. BabaChess does not practise it: all its terms are
computed, but its material-plus-PST part is **incremental** (`Make_Move` /
`Unmake_Move`).

## 3.10 Automatic tuning (Texel)

**Automatic tuning** replaces intuition with optimisation over data. The Texel
method minimises the gap between the actual game result and the evaluation's
output: labelled positions (`FEN;result`), score passed through a sigmoid,
coordinate descent on the mean squared error. It is a closed loop: each candidate
is measured by the real binary through `--eval-fens --params`, so the tuned
evaluation is the one that plays.

BabaChess provides `scripts/texel_extract.py` (a set of quiet positions from
self-play) and `scripts/texel.py` (tuning the scalars and the tables). The
project's lesson: a lower training error does not guarantee more strength, and a
set is kept only after an SPRT. A complementary path: SPSA, with the same binary.

## 3.11 BabaChess as the example

The evaluation lives in `BBChess.Eval` (`src/bbchess-eval.ads` / `.adb`):
incremental material plus PST, phase, terms per colour, subtraction, `Blend`.
`Static` returns the White-positive score and stays symmetric; `Evaluate` orients
it toward the side to move and adds the tempo. The scalar parameters are in a
`Params` table, exposed by `--dump-params` and loadable with `--params`, which
makes tuning possible without rebuilding the engine. The evaluation stays
**handcrafted, without NNUE**; neural networks are another path, mentioned later.

## See also

- `src/doc/evaluation.md`: technical reference (phase, terms, parameters, negative
  results).
- `src/doc/bitboards.md`: representation that makes the pawn and mobility terms
  natural.
- `src/bbchess-eval.adb`: `Positional_Score`, `Game_Phase`, `Blend`,
  `King_Safety`, `Scale_Factor`.
- `scripts/texel_extract.py`, `scripts/texel.py`: data and Texel tuning.
- Neighbouring chapters: `02-board-and-movegen-en.md`, `04-search-en.md`.
