# 8. Roadmap and limits

Building a chess engine is not one problem, it is a ladder. Each rung adds
strength and each is harder than the last. This chapter orders the levers by
return on effort, explains why the returns shrink, describes the ceiling that
handcrafted engines reached, and shows why NNUE moved it. It ends with a checklist
and with BabaChess as the concrete example.

## 8.1 The order of efforts

The path from a naive engine to a strong one follows a stable order: a step is
only worth taking once the previous one is solid.

| Order | Lever | What it buys |
|---|---|---|
| 1 | Correctness (perft, self-tests) | the engine plays legal chess at all |
| 2 | Speed (nodes per second) | more depth for the same time |
| 3 | Move ordering | a smaller tree for the same depth |
| 4 | Search aggressiveness (pruning, reductions, extensions) | a deeper effective search |
| 5 | Evaluation knowledge | better judgement at the leaves |
| 6 | Tuning | the last drops out of what you have |

**Correctness first, speed second.** A fast search over a broken move generator is
worthless, so the generator is trusted by counting (perft 1 to 5, self-tests), with
tests green and evaluation symmetric (chapter 7). Strength then scales with depth
and depth with speed: doubling the nodes per second is worth about half a ply, so
bitboards and a profiled hot path precede clever ideas (chapters 2 and 4).

**Ordering third, aggressiveness fourth.** Alpha-beta wants the good move first,
so hash move, MVV-LVA, killers, history and counter-move shrink the tree for free.
Then null move, reductions, futility, razoring and LMP buy depth by pruning what
rarely matters: the largest jumps, and where a wrong heuristic starts to cost more
than it earns.

**Evaluation fifth, tuning last.** Better judgement helps once the search is deep
enough (passed pawns, pawn structure, mobility, king safety). Tuning cannot create
knowledge the evaluation lacks, only move the parameters to a local optimum.

## 8.2 Why each step yields less

The ladder is ordered, and it is also a lesson in diminishing returns.

- **Correctness adds no strength by itself:** its payoff is that later
  measurements mean something.
- **Speed saturates:** the next doubling costs a project and is often
  unreachable once the obvious wins are taken.
- **Ordering and pruning overlap:** past saturation, another heuristic reshuffles
  nodes instead of deepening the search.
- **Evaluation terms overlap:** a new term usually measures what the search or an
  existing term already covers, and its cost can cancel its gain.
- **Tuning reaches a local optimum,** and Elo is logarithmic: the last hundred
  points cost far more than the first.

The order matters more than the catalogue: a weak search cannot exploit a fine
evaluation.

## 8.3 The classic ceiling

Handcrafted engines, whose evaluation is a sum of human-designed terms and whose
search is alpha-beta with heuristics, converged to a ceiling. The strongest, in
the Rybka era around 2008, sat at roughly **3100 to 3200 Elo** on the scales of
the time. The reasons are structural:

- The evaluation is **linear and additive**, so it cannot represent the
  interactions between terms where much real understanding lives.
- **Positional judgement** such as long-term plans or material compensation is
  hard to express as a hand-tuned term.
- **King safety** stays a known weak point: it depends on subtle interactions,
  not a single count.
- More terms **do not help** past a point: they overlap, and each costs speed the
  search would rather spend on depth.

At this level the remaining gaps are not a forgotten term, they are the shape of
the model.

## 8.4 What NNUE changed

**NNUE** (Efficiently Updatable Neural Network) broke the ceiling by changing the
model. The evaluation becomes a small neural network whose inputs encode the
position, typically each non-king piece relative to the two kings, trained on
millions of positions rather than written by hand. Adopting it gave the leading
classical engines on the order of **+400 Elo**, far more than any hand-added term.
It is a **paradigm shift**, not another term:

- the knowledge is **learned from data**, not designed by a human;
- it captures **interactions** a linear sum cannot;
- it stays fast because the network is **updated incrementally** as pieces move;
- progress then comes from **better data and training**, a skill a solo author can
  now attempt with open tools.

The other paradigm is the AlphaZero lineage: a deep network with Monte Carlo tree
search, learning from self-play, at a far higher compute cost. The handcrafted
route remains a complete education; going beyond it means NNUE, a different
project built on top of a classical one.

## 8.5 Realistic solo targets

A solo developer can go a long way with realistic targets.

- **A correct playing engine**, never illegal, surviving a GUI game: a few weeks
  of work with this guide and a test suite.
- **Around 2000 Elo**: a clean alpha-beta search, a simple tapered evaluation,
  reasonable time management.
- **2400 to 2600 Elo**, club strength: good move ordering, quiescence with SEE, a
  first serious evaluation.
- **2700 to 3000 Elo**: the full classical toolbox, measured and tuned.
- **The classic ceiling**, 3100 to 3200: reachable in principle, but years of work
  and constant measurement; **beyond it** usually means NNUE, a second project.

The last hundred Elo is the most expensive, and most of the effort goes into
accepting that most ideas do not work.

## 8.6 What works, what usually fails

| Worth doing | Usually fails or is marginal |
|---|---|
| Perft and a self-test suite before anything else | features on an unverified move generator |
| Profile, then make the hot path fast | micro-optimising code that is not hot |
| Ordering: hash, MVV-LVA, killers, history, counter-move | one more ordering heuristic past saturation |
| Quiescence with SEE and delta pruning | deep quiescence without a safety check |
| Aspiration, null move, LMR, futility, LMP | pruning and reductions without a stable baseline |
| Tapered evaluation: material, PST, pawns, mobility, king | rewriting the whole evaluation at once |
| Tuning on **self-play** data (Texel, SPSA) | tuning on human games; results reflect human mistakes |
| Validating every change with SPRT and enough games | concluding from a short match; 300 games resolve ~30 Elo |

Two habits separate a strong engine from a drifting one: **measure everything**,
because intuition about strength is unreliable, and **keep negative results**,
because knowing what fails stops you from retrying it later.

## 8.7 BabaChess as the example

BabaChess is a classical handcrafted engine, roughly at the level of GNU Chess
6.2.7. Its gains came in the order above: correctness from perft and 146
self-tests, speed from bitboards with PEXT attacks, then move ordering, then a
search lot, then a Texel-tuned evaluation.

The kept gains survived long SPRT runs. Counter-move and history ordering and time
management came first; a Texel tuning on self-play added more than a hundred Elo,
where the same method on human games had failed; later, passed-pawn knowledge and
a mobility term that excludes squares attacked by enemy pawns earned their place
one at a time.

The rest is a long list of measured and rejected ideas, kept behind neutral
parameters so the tree is unchanged when off: king-safety rework, phase mobility,
several knowledge terms, quiescence checks, a two-ply continuation history, an
improving flag, a material-imbalance term, incremental evaluation and a
transposition-table rewrite. The pawn hash table was dropped as the pawn is
already cheap, and profile-guided optimisation measured slower. On this engine
they met a **local optimum**, and the honest response was to record the
measurement and move on.

The ladder is real and the last rungs are where the work becomes measurement
rather than inspiration. A classical engine is a complete project, and its ceiling
is a property of the model, not a failure of its author.

## See also

- `02-board-and-movegen-en.md`: correctness, perft and the move generator.
- `03-evaluation-en.md`: the handcrafted evaluation and its known limits.
- `04-search-en.md`: the levers, from alpha-beta to reductions and pruning.
- `05-opening-book-en.md` and `06-endgame-tablebases-en.md`: the book and the
  tablebases, cheap strength at both ends of the game.
- `07-testing-en.md`: perft, self-tests, SPRT, Texel and SPSA.
- `src/doc/outils-et-tests.md`, `src/doc/evaluation.md`, `src/doc/recherche.md`:
  measurements, evaluation and search in detail.
- `src/doc/README.md` and `DEVELOPMENT.md`: the technical index and the internal
  logs behind these measurements.
