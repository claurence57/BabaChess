# BabaChess 1.5.0 — Release Notes

**BabaChess** is a chess engine written in **Ada 2012**, using a **bitboard**
board representation. It speaks **UCI** and **XBoard/Winboard** and runs on
64-bit **Windows** and **Linux**.

BabaChess is a fork of [AdaChess](https://github.com/adachess/AdaChess); see
`NOTICE.md` for provenance and licensing.

---

## What's in 1.5.0

**Strength this time.** Two search changes are in, and their combined effect was
measured at the released time control: **+19.0 ± 9.4 Elo** over 3 000 games at
`10+0.1` against 1.4.0 (LOS 100 %, interval excluding 0).

### ProbCut at non-PV nodes

At a non-PV node, outside check and from depth 5, a capture whose static
exchange value reaches a margin (170 cp) is searched with beta raised by that
margin and a depth reduced by four plies (at most eight captures). A probe that
reaches the raised bound refutes the node without the full-width search. The
raised bound is kept out of the mate band and the probe depth never drops below
one ply. Measured **+38.20 ± 14.29 Elo** at 20 000 nodes/move (SPRT PASS, H1 at
1 744 games); the more conservative setting (margin 200, three captures) was
neutral, so the gain comes from how many nodes get refuted, not from a tighter
bound.

### Scored transposition-table replacement

The two-way bucket used to keep the deepest entry and replace stale ones first.
Every slot now has a keep-score — depth, plus a bonus for an exact (PV) entry,
minus a penalty for an entry written by an older search — and the lower of the
two gives way. Proven when the table is under pressure (small `Hash`, long
games): **+8.08 ± 2.91 Elo** at 20 000 nodes/move with 8 MiB (SPRT PASS). At the
default 64 MiB the bench never saturates the table, so `--bench` is unchanged by
construction.

### Tunable time allocation

The clock policy (moves-to-go estimate, hard/soft multiple, share of the
increment) moved from constants into three parameters, `S_Tm_Div`,
`S_Tm_Hard_100`, `S_Tm_Inc_100`, whose defaults (30 / 200 / 75) reproduce the
previous behaviour exactly. This is infrastructure, not a strength claim: the
first experiment made with it — spending the ~30 % of the clock the engine left
unused (`div 20`) — was measured **negative** (−5.7 ± 15.9 Elo; the search gained
nothing and time losses went from 2 to 13) and is not enabled.

### Two evaluation terms, off by default

Outposts (`P_Outpost_Op`, `P_Outpost_Eg`) and the rook behind a passed pawn
(`P_RookBehind_Op`, `P_RookBehind_Eg`) are implemented, switchable and neutral at
their default 0. Given a hand-picked value both **lose** (−11.5 and −16.2 Elo);
given the values a Texel run found (outpost +20 middlegame / −12 endgame, rook
+6 / +20) the screen is +8.3 ± 12.7, i.e. not proven. They ship disabled.

### Tooling

`scripts/gen_balanced_openings.py` generates a diverse, roughly balanced opening
suite from random play-outs (material within a pawn, `|Static| ≤ 60`); it exists
because `openings.epd` is a curated 65-line suite and the engine is deterministic
at fixed nodes, which collapses self-play to a few correlated games — useless as
a tuning set.

### Breaking change for tooling

`--bench` node counts move: **455 176 / 1 784 546 / 5 214 141** at depths 9/12/14
(ProbCut prunes nodes by design). The 1.4.0 counts — 488 704 / 2 467 322 /
5 454 471 — are exactly restored by `S_Probcut 0`. Any external script that
compares node counts against 1.4.0 must account for this.

## Verification

`--selftest` **146/146** in the release, portable, checked and debug
(`-gnatwe`) builds; evaluation mirror symmetry 0 discrepancy over thousands of
positions (`scripts/sym_check.py`); documentation parity check green.

## Provenance of the numbers

Every measurement quoted above, including the ones that failed, is written up in
`DEVELOPMENT.md` sections 92 to 98 with its protocol, the binaries used and the
raw W–L–D counts.
