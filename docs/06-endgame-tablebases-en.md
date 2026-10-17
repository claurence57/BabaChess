# 6. Endgame tablebases

Endgames expose the limits of an engine's heuristics: a won KQvK goes missing, a
fortress is misjudged, and the fifty-move rule slips out of sight. Endgame
tablebases answer that directly: instead of estimating a position, they return
its exact result, win, draw or loss. This chapter covers what a tablebase is, the
measures it exposes (WDL, DTZ, DTM), the Syzygy format, probing during the search
and at the root, and the fifty-move subtlety. BabaChess is the running example.

## 6.1 What tablebases are

A tablebase is a **precomputed** set of results: for every legal position with few
pieces it stores the theoretical outcome, solved backwards from mate. There the
answer is a proof, not an evaluation.

The payoff is large: instead of searching a subtree and trusting a heuristic, the
engine asks one question and gets the truth. Endgames are exactly where
evaluation is weakest, since material is thin and positional terms stop
discriminating. The cost is space and coverage: a table only reaches N pieces,
and stores each position's value, not a plan.

## 6.2 WDL, DTZ, DTM

Three measures answer different questions; confusing them causes real bugs.

- **WDL** (Win / Draw / Loss): theoretical result from the side to move, ignoring
  the fifty-move rule. It says *whether* a position is won, not how long it takes.
- **DTZ** (Distance To Zero): plies to the next **zeroing move** (pawn move or
  capture) while keeping the WDL result; the measure tied to the fifty-move rule.
- **DTM** (Distance To Mate): plies to checkmate. Older formats (Nalimov,
  Edwards) exposed it; Syzygy does not.

WDL is enough to prune, since it gives a subtree's exact score; DTZ converts a win
once the counter runs. A common design, and BabaChess's, probes WDL everywhere and
keeps DTZ for the root.

One nuance: Fathom returns five codes, `0` loss, `1` blessed loss, `2` draw, `3`
cursed win, `4` win. A **cursed win** is won only by ignoring the fifty-move rule,
a **blessed loss** its mirror; both are draws in practice, and a careful engine
treats them so.

## 6.3 The Syzygy format and piece counts

**Syzygy** is the modern standard: two files per material configuration, `.rtbw`
for WDL and `.rtbz` for DTZ, both heavily compressed through board symmetries and
a compact indexing of piece placements. The 3-4-5-piece set fits in about a
gigabyte.

Counts scale brutally: 3-4-5 pieces about 1 GB, six about 150 GB, seven about
18 TB. WDL files are far smaller than DTZ, since WDL needs three values and DTZ a
distance.

## 6.4 Probing during the search

Probing means querying the loader for a position's value. The probe sits near the
top of the recursive function, after the repetition test, so a solved position
returns an exact score without expanding any child. Three guards gate it: tables
loaded and enabled; no more pieces than the largest loaded set; **no castling
rights**, which WDL does not describe.

On success the outcome replaces the search score, encoded just below mate and
adjusted by the current ply, so the engine prefers the nearest win and postpones
the loss; the search stops as soon as such a score returns. On failure it runs on
as if no tablebase existed.

## 6.5 Probing at the root

WDL says a position is won, not how to win it inside fifty moves. The remedy is a
**root probe**: the engine asks for a move, one that keeps the WDL result while
minimising the distance to zero. It is rare by design: heavier than a WDL probe,
needing DTZ data, and usually not thread-safe, so it runs once, before the normal
search, only in the endgame zone.

## 6.6 The fifty-move rule and why DTZ matters

WDL is computed with the halfmove counter at zero, so a "win" means won if the
fifty-move rule never bites, which is not the same as won under the rules. A
WDL-only engine can know a position is winning, march towards it, never play a
pawn move or capture, and draw at fifty: the value right, the win lost.

**DTZ** closes the gap, since a zeroing move resets the counter and a DTZ-aware
engine prefers the line that resets it in time. The counter is part of the game
state, so the probe receives its current value, and a cursed or blessed result
already accounts for it. Perfect play under the rule needs finer distinctions than
one DTZ value, but minimising the distance to zero and treating cursed and blessed
outcomes as draws is the sound approximation.

## 6.7 Using a probing library, size and availability

Nobody reimplements Syzygy to ship an engine; the decoding is intricate and
error-prone. **Fathom** (MIT) is the common choice, a small C reader with a few
entry points for WDL and root DTZ; other languages have tooling libraries
(python-chess). BabaChess vendors Fathom behind a thin binding, keeping the engine
portable and the licence boundary clean (see `NOTICE.md`).

Availability matters. The 3-4-5-piece set is easy to store, six pieces a serious
disk commitment, seven a multi-terabyte affair often served from a network mount.
Many engines ship inert by default: without files, probing is never attempted.
Partial sets are normal, and since files are memory-mapped and read on demand,
probing also costs disk latency, another reason to guard it.

## 6.8 Limitations

- **No castling.** WDL and DTZ tables describe only positions without castling
  rights.
- **Piece ceiling.** Above the largest loaded set, the probe is silent.
- **Fifty-move subtlety.** Without DTZ, a "win" can still be drawn.
- **Value, not plan.** No readable plan, no mate distance.
- **Disk-bound.** Large sets need space and fast storage.

## 6.9 BabaChess as the example

BabaChess probes Syzygy through `BBChess.Syzygy` (`src/bbchess-syzygy.ads` /
`.adb`), a thin Ada binding over the C wrapper `src/fathom/bbchess-tbwrap.c`,
itself over the vendored **Fathom** (MIT, `src/fathom/`; see `NOTICE.md`). The API
is five subprograms: `Init (Path, Ok)`, `Free`, `Largest`, `Enabled` and
`Probe_WDL (Position)`.

**WDL is probed in the search**, at the top of `Negamax` after the repetition
test, guarded by `Enabled` and a piece count no greater than `Largest`. Castling
positions are refused and the halfmove clock is sent as zero, as WDL assumes. A
win becomes `TB_Win - Ply` (`TB_Win = 20_000`, below mate, above any normal
evaluation), a loss its negation, and the blessed, cursed and drawn codes collapse
to `0`, a deliberately prudent reading. With the three-piece tables, a white KQvK
returns 19999 at depth 2.

**DTZ is opt-in at the root.** `Has_DTZ` and `Probe_Root_Move` wrap Fathom's
`tb_probe_root`; enabled by the `S_Syzygy_Root` parameter (`--params` with
`S_SYZYGY_ROOT 1`), off by default, it fires only in the fifty-move zone (halfmove
at least `S_Syzygy_Root_Min_Hm`, default 80) with at most
`S_Syzygy_Root_Max_Pieces` men. Not thread-safe, it runs once at the root, with
the halfmove clock passed as the fifty-move context.

Configuration is forgiving. `--syzygy <dir>`, or UCI `setoption name SyzygyPath
value <dir>`, points at the tables, and the path may list several directories
separated by the platform separator (`:` on Unix, `;` on Windows). An invalid path
is not fatal: `Init` returns `Ok = False`, `Largest` stays 0, `Enabled` is false,
and the engine plays on. `--selftest` and `--bench` never probe them.

## See also

- `src/doc/finales-en.md`: reference documentation of the BabaChess tablebase layer.
- `src/bbchess-syzygy.adb`, `src/bbchess-syzygy.ads`: the Ada binding.
- `src/fathom/`: the vendored Fathom probe (MIT); see `src/fathom/LICENSE`,
  `NOTICE.md`.
- Syzygy Bases: <https://www.chessprogramming.org/Syzygy_Bases>.
- `src/doc/README-en.md`: the index of the technical documentation.
- Neighbouring chapter: `05-opening-book-en.md`; the rest are in `docs/`.
