# 4. Search

Evaluating the current position is not enough: an engine must anticipate the
opponent's reply. Search explores the tree of moves, weighs the answers and
returns the move whose line leads to the best position. BabaChess implements this
in `BBChess.Search` (`src/bbchess-search.adb`), with `BBChess.See`
(`src/bbchess-see.adb`) for quiescence: a **negamax alpha-beta** shrunk by move
ordering, the transposition table and a family of prunings. This chapter
describes the ideas; `src/doc/recherche.md` keeps the details of the choices.

## 4.1 The game tree and negamax

Search models the game as a tree: each node is a position, each edge a legal
move, and depth is counted in plies. At the leaves, a static evaluation judges
the position; above, each side picks the continuation most favourable to itself.
**Minimax** thus alternates a maximum (my moves) and a minimum (yours), and
**negamax** simplifies it: if the score is always from the side to move's point
of view, the value of a node is the maximum, over all legal moves, of the
**opposite** of the child's value:

    value(position) = max( -value(child) )   for every playable move

So a high score is always good *for the side that has to move*. Mate scores are
offset by the number of plies so the quickest is preferred, a node with no legal
move returns mate or stalemate, and forced draws (fifty-move rule, insufficient
material, repetition) are handled before the transposition table. In BabaChess,
`Negamax` hands over to `Quiescence` at depth zero.

## 4.2 Alpha-beta and the window bounds

Exploring the whole tree is impossible: the number of nodes grows exponentially.
**Alpha-beta** does not compute a better value, it avoids work. Each node receives
a window `[Alpha, Beta]`:

- **Alpha** is the best value already guaranteed to the side to move higher up.
  Below it, the node has nothing to offer: that is a **fail low**.
- **Beta** is the bound the opponent will not let be exceeded. Reaching or
  exceeding it is a **fail high**: the branch can be cut without being finished.

A branch that cannot change the root's choice is therefore abandoned. In the best
case, alpha-beta visits roughly the square root of minimax's nodes, if the right
move is examined first; in the worst case, it falls back on full minimax. The
whole strength of the algorithm rests on the **order** of the moves, hence the
outsized role of move ordering. BabaChess applies this window at the root
(`Root_Search`) and at the internal nodes (`Negamax`).

## 4.3 Move ordering: the force multiplier

Alpha-beta is exact, but its speed depends entirely on ordering: ordering well
does not make the search more correct, it makes it far faster at equal depth,
hence deeper in equal time. The heuristics are retried in this order:

- **Transposition-table move**: the best move already found for this position. It
  is the best predictor there is.
- **Promotions**, then **captures** ranked by **MVV-LVA** (*Most Valuable Victim,
  Least Valuable Attacker*): the most valuable piece taken by the least valuable
  one. A capture that is losing in the static-exchange sense goes after the quiet
  moves.
- **Killers**: two quiet moves that already caused a beta cutoff at the same ply
  elsewhere.
- **Counter-move**: the reply that refuted the opponent's previous move.
- **History and continuation history**: the remaining quiet moves, ranked by a
  remembered score keyed by (piece, square) or (previous move, current move). A
  move that cut earns a bonus, a fruitless move gets a penalty.

These tables learn as the search runs and are aged (history is halved each
iteration). The circle is virtuous: ordering better produces more cutoffs, hence
more depth, hence better table entries. All of this lives in `Order`.

## 4.4 Iterative deepening and aspiration windows

`Iterative_Search` does not search straight to the maximum depth: it starts at
depth 1, then 2, 3, and so on. Each completed iteration supplies the best move,
which becomes the ordering hint for the next, and the engine always has a valid
answer (the last completed iteration) even if it is interrupted.

The window is then tightened: **aspiration windows** bracket the previous score by
a small margin (BabaChess: 40 centipawns). If the result falls inside the window,
fine; otherwise only the crossed bound is widened and the iteration is relaunched,
doubling the margin on each failure until the full window is back. An iteration
also stops early on a mate or a tablebase result. The search is interruptible: it
polls the deadline every 1024 nodes or so and keeps the last completed iteration.

## 4.5 Principal variation search (PVS)

**PVS** (Principal Variation Search, or scout) assumes the first move, the best
ordered, is the best:

1. The first move is searched with the **full window** `[-Beta, -Alpha]`.
2. Every later move is first searched with a **null window**
   `[-Alpha - 1, -Alpha]`, more severe and therefore cheaper. If it stays below
   Alpha, move on; if it exceeds it, it is **re-searched with the full window** to
   obtain its true score.

The reasoning is "presumed guilty unless proven otherwise". The method is only
correct if the first move really is the best most of the time, which comes back to
ordering. `Root_Search` applies the same strategy at the root.

## 4.6 Transposition table

Many paths lead to the same position (e4 then Nf3, or Nf3 then e4). The
**transposition table** remembers the result of a position already seen, indexed
by its **Zobrist key** (a 64-bit digest kept incrementally, see
`src/doc/bitboards.md`), and avoids recomputing it.

Each entry holds the full key, the remaining depth, the **bound** of the result
(`Exact`, `Lower_Bound` or `Upper_Bound`), the score (mate scores normalized by
the ply), the best move and an age. **Replacement** is a real design choice:
BabaChess uses two-way buckets, keeps the deeper entry and replaces stale entries
first through a generation counter (*aging*). The cutoff is applied only if the
entry is at least as deep as the search, but the stored move is extracted even
without a cutoff, because it then serves for ordering.

## 4.7 Pruning and reductions at shallow depth

Ordering shrinks the tree; pruning cuts it: judge that a branch cannot change the
result and do not search it, or search it less deeply. All these techniques first
check that we are **neither in check nor in a mate position**.

- **Null move**: pass the turn and search at reduced depth; if even without
  moving we exceed Beta, the cutoff is warranted. Forbidden in pawn endings,
  where zugzwang makes the "pass" misleading.
- **Reverse futility**: if the static evaluation already reaches Beta with a
  depth-dependent margin, the node is returned as is.
- **Futility**: a quiet move whose evaluation plus a margin cannot reach Alpha is
  skipped.
- **Razoring**: if the static evaluation is far below Alpha, verify with a
  quiescence search and return it if it does not climb back to Alpha.
- **Late move pruning (LMP)**: late quiet moves (beyond `4 + depth²`) are not
  searched; ordered last, they almost never improve the window.
- **Late move reduction (LMR)**: a late quiet move is searched at reduced depth,
  by a logarithmic formula (`0.75 + ln(depth) × ln(rank) / 2.25`). It is reduced
  less on the principal variation, more in a null-window node; killers and
  checking moves are never reduced. Any fail-high is re-verified at full depth,
  since the reduction can create a false cutoff.

## 4.8 Extensions and mate-distance pruning

Conversely, an **extension** deepens a branch judged important. BabaChess extends
only one case: a node where the side to move is **in check** searches its evasions
one ply deeper, because they are forced and a sequence of checks must not be
truncated by the horizon. The extension is bounded by the ply.

**Mate-distance pruning** works on the bounds: no node can be worth better than a
mate found at the current ply, nor worse than a mate suffered right away. Alpha
and Beta are therefore bounded by `-Mate_Score + Ply` and `Mate_Score - Ply - 1`,
and we cut if the bounds cross.

## 4.9 Quiescence search

At the edge of the horizon, evaluating bluntly is dangerous: the position may sit
in the middle of a series of exchanges, and the static evaluation does not see its
end. **Quiescence** extends the search by searching only **tactical** moves
(captures and promotions) until the position calms down.

Out of check, evaluate the position (**stand pat**): if it reaches Beta, cut; if it
exceeds Alpha, adopt it. In check, stand pat is illegal and every evasion is
searched. **Delta pruning** skips a capture whose victim plus a margin does not
reach Alpha, and **SEE pruning** skips a capture whose static exchange is losing.

**SEE** (Static Exchange Evaluation) lives in `BBChess.See`: it replays the
capture sequence on a square, picks the cheapest attacker while excluding pinned
pieces, only admits the king last, and lets each side decline to recapture. The
resulting value serves both quiescence and capture ordering.

## 4.10 The trade-off of selective depth

Every pruning and reduction trades accuracy for depth. Each cut risks missing a
tactic that would have flipped the evaluation; in exchange, the tree shrinks and
the engine sees further. Too timid, a pruning gains almost nothing; too
aggressive, it leads the search astray. The right question is not "is it rigorous"
but "does it win games".

BabaChess follows that discipline: any change must keep `--selftest` green, leave
`--bench` stable, then pass an SPRT campaign of several hundred games. Several
classic techniques were tried and then reverted after measuring neutral or
negative (singular extensions, extending every checking move, internal iterative
deepening, quiet checks in quiescence). The result is a set of techniques proven
in match play, adjustable through `--params`.

## See also

- `src/doc/recherche.md`: the reference documentation of the search.
- Code: `src/bbchess-search.adb` and `src/bbchess-search.ads` (negamax, PVS,
  ordering, pruning, Lazy SMP), `src/bbchess-see.adb` (static exchange).
- `src/doc/bitboards.md`: the Zobrist key, the basis of the transposition table.
- `src/doc/evaluation.md`: the evaluation called at the leaves.
- `src/doc/finales.md`: the Syzygy WDL probe, which short-circuits the search.
- `src/doc/outils-et-tests.md`: `--selftest`, `--bench`, `--params`, SPRT/SPSA.
- `src/doc/README.md`: the index of the technical documentation.
- The other chapters of the guide are in the `docs/` directory.
