# 5. The opening book

An engine left to its own devices sometimes commits, in the first moves, to weak
lines that its static evaluation does not penalise early enough. The opening
book corrects that bias: it does not think, it plays a known move and hands back
to the search. It is an auxiliary component, queried **before** the search takes over,
in the same way as endgame tablebases. This chapter explains what a book is for,
how it is represented, how it is probed and how to build one. BabaChess is the
example.

## 5.1 Why a book

An opening book brings three distinct things.

- **Avoiding early mistakes.** The opening is full of traps that static
  evaluation judges poorly; a proven line avoids repeating a dubious move that
  nothing punishes early enough.
- **Saving time.** A book move is played instantly: the time saved is reinvested
  later, in the middlegame, where calculation really matters.
- **Varying.** A weighted book offers several moves per position and draws one
  at random, which avoids replaying the same game every time.

The book replaces neither evaluation nor search: it precedes them, over a
handful of plies only.

## 5.2 Book formats and Polyglot `.bin`

A book is a table mapping a position to a list of moves. Forms vary: lists
derived from PGN, or compiled binary files. The **Polyglot `.bin`** format has
become the de facto standard: simple and compact, it is read by most engines and
interfaces.

A Polyglot book is a binary file with no header, made of **16-byte entries**, in
**big-endian** order and **sorted by increasing key**:

| Size | Field | Role |
|---|---|---|
| 8 | `key` | Polyglot Zobrist key of the position |
| 2 | `move` | encoded move (from, to, promotion) |
| 2 | `weight` | relative frequency of the move |
| 4 | `learn` | reserved, ignored |

Sorting by key allows a **binary search**, hence a probe in `O(log n)` even in a
book of several hundred thousand entries. The `weight` field acts as a relative
probability: a move played often weighs more than a rare move. This
compatibility lets you reuse a public book with no conversion.

## 5.3 How probing works

Probing a book means looking up a position and pulling a move from it. First you compute
the **Polyglot Zobrist key** of the position. This is not the transposition-table
key: the format fixes its own convention, with a table of frozen constants and a
particular rule for en passant captures, because the book must match byte for
byte what external generators produced.

Probing then runs in several steps:

1. compute the key of the position;
2. find that key by binary search in the sorted table;
3. scan the contiguous entries with the same key, summing their weights (each
   weight being floored at 1, so an entry with weight zero stays playable);
4. draw a random number in that sum and select the matching entry: that is the
   **weighted choice**;
5. decode the move and **check that it is really legal**.

The last step is essential: a book may hold stale moves or a badly encoded
promotion. So the probe never returns an illegal move; if the key is absent or
the decoded move is not legal, the book is silent and the normal search starts.

Upstream, the driver decides **whether to consult** the book: it must be enabled
and loaded, and the position must not be too far advanced. An engine usually
limits probing to about fifteen plies.

## 5.4 Building a book from a public database

You build a book by counting the moves played in a large database of games. The
**Lichess** database, released under **CC0** (public domain dedication), is
reusable, including in a GPL project. You pick a period, tally for each position
the moves played and their outcome, then turn those statistics into Polyglot
entries, with a weight derived from frequency and score.

A raw database holds a lot of noise: without **filters**, the book is not
useful. Typical settings:

- **player level**: minimum Elo floor for both sides;
- **time control**: discard games that are too fast;
- **depth**: keep only the first plies;
- **frequency**: minimum occurrences of a position and of a move;
- **move share**: discard marginal moves and those with too weak a result;
- **width**: cap the number of moves per position.

An optional filter through a strong engine also drops dubious moves, but every
filter tightens the book and can erase important lines. The **size / quality**
trade-off is the real subject: too strict a threshold misses common replies, too
lax a threshold lets weak moves in. So calibrate the thresholds against a
coverage target, then validate the result.

## 5.5 Light book or deep book

The size of the book is not a goal in itself, it is a trade-off.

- A **light book** loads fast, fits in little memory and covers the main lines;
  it is enough to give the engine a sound opening.
- A **deep book** covers more variations, including rare ones, at the cost of a
  bigger file, a slower load and a greater risk of moves of uneven quality.

For an engine that plays, a modest, clean book beats an encyclopaedic, badly
filtered one; for analysis, a wider book has its place.

## 5.6 Book and fairness in a match

The book changes game results: it matters when measuring an engine's strength.

- **Neutralise the book on both sides.** Otherwise the comparison no longer
  measures the search but the opening.
- **Do not start from the initial position alone.** A game launched from the
  start is biased in favour of White, whose win rate approaches 70%. Use an
  **opening suite** and play each line in both colours.

In other words, the book is there to **play**, not to measure raw strength.

## 5.7 BabaChess as the example

BabaChess illustrates each point. The module is called `BBChess.Polyglot` and
lives in `src/bbchess-polyglot.adb` / `src/bbchess-polyglot.ads`. It implements
the Polyglot `.bin` format and is probed **before** the search, with a limit of
**16 plies**: beyond that, the search takes over.

Three routes open a book: the option `--book <file>`, conventional locations
loaded by default (including `books/book.bin`), and the UCI options `OwnBook`
(enabled by default) and `BookFile`. A bundled book of **0.58 MiB** is provided:
**38,191 entries** generated from the Lichess **CC0** database, not versioned
because it is reproducible. `scripts/make_book.py` builds it and
`scripts/fetch_book.sh` fetches a ready-made CC0 book.

One notable point: `--selftest` does **not** load the book; validation checks the
**Polyglot Zobrist key**, compared against reference values produced by an
external implementation.

## See also

- `src/doc/ouvertures-en.md`: the reference documentation of the BabaChess book
  (format, Polyglot key, probing, configuration, validation).
- `books/README-en.md`: provenance of the bundled book (Lichess CC0), settings,
  regeneration and validation.
- `scripts/make_book.py`: building a Polyglot book from Lichess, with the filters
  and the validation.
- `scripts/fetch_book.sh`: downloading a ready-made CC0 book.
- Code: `src/bbchess-polyglot.adb` and `src/bbchess-polyglot.ads` (Polyglot key,
  loading the `.bin`, weighted probe).
- `src/doc/README-en.md`: the index of the technical documentation.
- Neighbouring chapter: `04-search-en.md`; the other chapters are in `docs/`.
