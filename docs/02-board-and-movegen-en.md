# 2. Board representation and move generation

A chess engine answers two questions constantly: "where are the pieces?" and "which moves
are legal?". How the board is represented therefore decides a great deal, from search speed
to how simple the code stays. This chapter covers the two main families of board
representation, the construction of attacks, the generation of moves and their validation by
perft, with BabaChess as a concrete example.

## 2.1 Mailbox or bitboards

The **mailbox** representation describes the board as an array of 64 squares, each holding at
most one piece. Moving a piece means writing a value into a square: easy to understand, but
slow, because walking a rook's rays happens square by square.

The **bitboard** representation replaces the array with **64-bit integers**, one bit per
square. Set operations (free squares, a colour's occupancy, possible targets) become plain
`or`, `and`, `not`, applied to all 64 squares at once. This is BabaChess's approach, where
`Bitboard` is a modular type: `type Bitboard is mod 2 ** 64;` (see `src/bbchess-board.ads`).

### Square indexing

A single convention, used everywhere:

- a square's index is `Rank * 8 + File`;
- `File 0` = file A, `Rank 0` = rank 1 (White's home rank);
- `bit 0` = a1, `bit 63` = h8;
- increasing the index goes north: `+8` per rank, `+1` per file.

In Ada, `File_Of (S) = S mod 8` and `Rank_Of (S) = S / 8`. The a1-is-the-LSB convention is
the modern bitboard one; it makes the bulk pawn shifts especially convenient (section 2.4).

### Piece encoding

A piece is a small enumeration type, `Piece_Type`, holding the twelve concrete pieces. The
trick is the **ordering**: the six white pieces (`White_Pawn .. White_King`) then the six
black ones. Colour and kind then follow from modular arithmetic, with no table: `Color (P)`
compares the position against 6, `Kind (P)` takes the position modulo 6, and
`Make (Colour, Kind)` does the reverse (see `src/bbchess-pieces.ads`).

## 2.2 Loading a position: FEN and incremental state

The standard entry point is **FEN** (Forsyth-Edwards Notation): piece placement, side to
move, castling rights, en passant square, halfmove and fullmove counters.
`src/bbchess-fen.adb` splits it field by field.

Placement is read from rank 8 down to rank 1, each digit counting empty squares. The parser
is **strict**: a rank that does not hold exactly eight squares, a missing `/` or a ninth rank
are all rejected, because a silent misalignment would corrupt everything after it. Before
returning the position it checks invariants: exactly one king per side, no pawn on the first
or eighth rank, consistent material, and above all that the side not to move is not left in
check (a capturable king would signal an illegal FEN).

Beyond the squares, a position carries **incremental state** maintained by
`Put_Piece` / `Remove_Piece` / `Move_Piece`:

- `All_Occ` (total occupancy) and `Color_Occ` (per colour), updated bit by bit on every
  mutation, never recomputed by scanning;
- the `Squares` table, giving a square's piece in O(1);
- `Key`, the **Zobrist** key used by the transposition table (`src/bbchess-hash.ads`);
- `Material`, the material sum together with the piece-square tables.

The `Squares` table is only meaningful on an occupied square: that invariant must be
respected when reading it.

## 2.3 Attacks: leapers and sliders

Generating a move is mostly about computing attacks. Two families are handled separately.

### Leapers: knight, king, pawns

A **leaper**'s attacks do not depend on occupancy: a knight always attacks the same eight
squares from a given square. They are therefore precomputed once at elaboration, in
`src/bbchess-attacks.adb`. The body starts from delta arrays `(dFile, dRank)` and applies
`Build_Leaper`: for each delta, check that the square stays on the board, then set the
matching bit.

Pawns are treated separately, since a white pawn attacks upward and a black pawn downward:
two distinct tables, indexed by colour. A useful consequence: to know whether a square is
attacked by a pawn, you read the **opposite** colour's table, using the relation backwards.

### Sliders: bishop, rook, queen

Bishop, rook and queen have attacks that **depend on occupancy**: a blocker stops the ray.
The usual fix is an **indexing** scheme: compress the relevant occupancy into a small integer,
which indexes a precomputed table. BabaChess uses `PEXT` (BMI2), which extracts the occupancy
bits falling inside a mask and packs them together. Because `PEXT` is a **bijection** between
the subsets of the mask and the indices `0 .. 2^n - 1`, there are no collisions, hence no
"magic number" to search for: unlike magic bitboards, the table fills directly. A rook needs
up to 12 index bits (4095 entries), a bishop up to 9 (511). The queen has no table of its
own: `Queen_Attacks` is the `or` of the rook and bishop attacks.

Two square tables complete the set, computed from empty-board attacks: `Between (A, B)` (the
squares strictly between A and B) and `Line (A, B)` (the full line through them). They drive
check detection and pins. In `portable` mode, `PEXT` gets a software fallback in the C shim
`src/bbchess-bits.c`, so move generation is unaware of the build mode.

## 2.4 Generating moves: pseudo-legal, then legal

BabaChess's strategy is "correctness first": `Generate_Pseudo_Moves` produces every move that
respects how the pieces move, then `Generate_Legal_Common` drops the ones that would leave
the king in check (see `src/bbchess-movegen.adb`).

### Pawns: bulk shifts

Pawn pushes and captures are computed for **all pawns at once**, by shifting the bitboard.
Since the rank occupies the high bits, advancing one rank means multiplying by 256 (and
retreating, dividing). File masks (`File_A_BB`, `File_H_BB`) prevent captures that would wrap
around from one edge to the other. The four promotion squares come out of `Emit_Promotions`,
which emits queen, rook, bishop then knight.

For the other pieces, their bits are iterated and friendly squares removed:
`Bishop_Attacks (From, Occ) and not Own`, and likewise for rook, queen, knight and king. The
"tactical" modifier keeps only enemy squares, for quiescence.

### Legality filter

The filter avoids a systematic `Make_Move` / `Unmake_Move` by working on bitmasks:

1. `Attackers_To` enumerates the enemy pieces attacking the king: that is the `Checkers`
   bitboard.
2. In **single check**, `Check_Mask` is the checker's bit plus `Between (king, checker)`: the
   move must capture or interpose. In **double check**, `Check_Mask = 0`: only the king may
   move.
3. `Pin_Mask` computes the **absolutely pinned** pieces: a piece is pinned when it is the
   only blocker between its king and an enemy slider of matching direction.
4. A non-king move is kept only if it lands in `Check_Mask` and, when the piece is pinned, if
   it stays on `Line (king, from)`.
5. The king may not step onto an attacked square; the test removes the king from the
   occupancy, so discovered attacks are counted.
6. **En passant** goes through a full make/unmake, because it can uncover an attack along the
   rank.

When there is neither check nor pinned piece, every non-king move is legal as generated: that
is a fast path that skips the filter.

## 2.5 Special moves

Three rules escape the "from to" scheme.

- **Castling**: appended after the king moves, only if the squares in between are empty and
  unattacked. King-side and queen-side are two distinct flags.
- **En passant**: the target square is empty, so it is absent from the bulk captures; the
  attacking pawns are recovered through the opposite colour's pawn table.
- **Promotion**: one displacement spawns four moves, one per promotion piece.

A move is a small `Move_Type` record (from, to, piece, promotion, flag), with a compact
32-bit form for the transposition table. `Make_Move` returns an `Undo_Info` that lets
`Unmake_Move` restore the previous state exactly: the position stays a plain copyable value,
which simplifies perft, search and FEN. See `src/bbchess-moves.ads`.

## 2.6 Perft: the ground truth

How do you know a move generator is correct? You count the nodes of a tree of legal moves at
a fixed depth: that is **perft**. `Nodes` (`src/bbchess-perft.adb`) is recursive: depth 0
returns 1, depth 1 returns the move count directly, otherwise it enumerates the moves, calls
`Make_Move`, descends to `Depth - 1`, then `Unmake_Move`.

Perft exercises exactly the building blocks of this chapter: attack tables, the legality
filter, special moves, make/unmake. If a sliding ray skips a blocker, if a file mask is wrong
or if a pin is forgotten, the count drifts. It is compared against known values:

| Position | Depth | Expected |
|---|---|---|
| Start | 1 to 5 | 20, 400, 8 902, 197 281, 4 865 609 |
| Castling | 1 to 3 | 48, 2 039, 97 862 |
| En passant | 1 to 3 | 14, 191, 2 812 |
| Promotions | 1 to 2 | 44, 1 486 |

Golden rule: any change to move generation must keep `--selftest` green and the perft counts
**unchanged**.

## See also

- `src/doc/bitboards.md`: the detailed technical description of the representation and the
  attacks.
- Code: `src/bbchess-board.ads` / `.adb`, `src/bbchess-attacks.adb`,
  `src/bbchess-movegen.adb`, `src/bbchess-moves.ads` / `.adb`, `src/bbchess-perft.adb`,
  `src/bbchess-fen.adb`, `src/bbchess-hash.ads`.
- Guide index: `README-en.md`. Neighbouring chapters: `01-introduction-en.md`,
  `03-evaluation-en.md`, `04-search-en.md`, `05-opening-book-en.md`,
  `06-endgame-tablebases-en.md`, `07-testing-en.md`, `08-roadmap-and-limits-en.md`.
- `src/doc/recherche.md` and `src/doc/outils-et-tests.md`.
