# BabaChess 1.4.0 — Release Notes

**BabaChess** is a chess engine written in **Ada 2012**, using a **bitboard**
board representation. It speaks **UCI** and **XBoard/Winboard** and runs on
64-bit **Windows** and **Linux**.

BabaChess is a fork of [AdaChess](https://github.com/adachess/AdaChess); see
`NOTICE.md` for provenance and licensing.

---

## What's in 1.4.0

**Speed, Syzygy auto-configuration, and evaluation tooling.** No strength gain
is claimed: the search tree is unchanged (`--bench` node counts are identical to
1.3.3). This release removes call overhead and makes tablebases easier to use.

### SEE inlined

The static exchange evaluation sits on the hot move-ordering/quiescence path but
LTO kept it out of line (about **6 % of benchmark self time**, mostly call and
cache-line churn around the board arrays). `pragma Inline_Always` on
`Static_Exchange_Value` emits it at each call site: the symbol is gone (checked
with `nm`) and the tree walk is untouched. Measured (interleaved `--bench`
runs): **+1.1 % median / +2.3 % best-of-9** knps. The debug-only `-gnatwr`
warning about the unenforced `Pre` aspect is silenced locally so the
`-gnatwe` CI build stays clean.

### Syzygy auto-configuration

`Load_Default_Syzygy` probes the conventional locations at startup — `syzygy`,
`<exe>/syzygy`, `~/.babachess/syzygy`, `<exe>/../syzygy` — for `.rtbw` files and
enables them **silently**, exactly like the default book search. An explicit
`--syzygy <dir>` or `setoption name SyzygyPath` still wins; with no tables the
probe is a no-op, so `--bench`/`--selftest` are unchanged.

### History aging

The per-iteration aging sweep now skips the first iteration: `Init_Context`
zeroes both history tables at the start of every search, so the first sweep
would halve ~598k zeros for nothing. Behaviour-identical (`0 / 2 = 0`).

### Evaluation tooling

- **`scripts/elo_rate.py`** — anchored Elo estimate: one rating fitted by
  maximum likelihood with the opponents fixed at their nominal Elo, 95 %
  interval from the observed Fisher information, per-opponent table, `--json`.
- **`scripts/elo_eval.sh`** — bookless gauntlet over the opening suite against a
  pool (`scripts/elo_pool.conf`), feeding the PGNs to the estimator.
- **`scripts/spsa.py --only <regex>`** — tune a single parameter.
- **`scripts/sprt_params.sh`** — the temporary `--params` wrapper is now removed
  on exit.
- **`pgn/`** — the 800 games of the first anchored evaluation, zipped, with a
  README (setup, results, caveats).

### Verification

- `--selftest` **146/146**.
- `--bench 9/11/12` = **488 704 / 1 166 698 / 2 467 322** nodes (identical to
  1.3.3).
- `scripts/sym_check.py`: 3 000 positions, 0 asymmetry.

---

## CPU requirements

| Build | Requires | Speed |
|---|---|---|
| `release` (x86-64) | A CPU with **BMI2** and **POPCNT** (Intel Haswell 2013 / AMD Zen 2017 or newer) | Fastest |
| `portable` (x86-64) | Any 64-bit x86 CPU | ~25% slower (software PEXT fallback) |

- If the `release` binary crashes with an **illegal instruction** on startup,
  your CPU lacks BMI2/POPCNT: download the **`portable`** build instead.
- **AMD Zen 1 and Zen 2** implement PEXT in microcode, making it slow. On those
  CPUs the `portable` build (software PEXT) can be **faster** than `release`;
  try both.
- Only 64-bit x86 (x86-64) binaries are provided for 1.4.0. There is no 32-bit,
  ARM or POWER build.

---

## Download

Pick **one** archive for your OS:

```
babachess-1.4.0-linux-x86_64-bmi2.tar.gz       Linux, modern Intel/AMD (BMI2+POPCNT)
babachess-1.4.0-linux-x86_64-portable.tar.gz   Linux, any x86-64
babachess-1.4.0-windows-x86_64-bmi2.zip        Windows, modern Intel/AMD
babachess-1.4.0-windows-x86_64-portable.zip    Windows, any x86-64
```

Verify integrity against the `SHA256SUMS` file published with the release.

Each archive contains: the engine binary, `LICENSE`, `NOTICE.md`, the Fathom
MIT licence (`src/fathom/LICENSE`), both READMEs (`README.md`, `README-fr.md`),
both CONTRIBUTING files, these release notes, the documentation (`docs/` and
`src/doc/`, in French and English), and the bundled book at `books/book.bin`.

The engine **finds `books/book.bin` by itself**: keep the `books/` directory
next to the executable, or pass an explicit path with `--book <file>` /
the UCI option `BookFile`.

---

## Quick start with a GUI

The engine is a command-line program that talks the **UCI** protocol (and
XBoard). Configure it as an external engine in your favourite GUI.

### Arena (Windows)

1. `Engines → Install New Engine…`
2. Select `babachess.exe`. When asked for the protocol, choose **UCI**.
3. The engine appears in the engine list. Configure `Threads` and `OwnBook`
   per your preference.

### Cute Chess / Cute Chess CLI (Linux, Windows, macOS)

GUI: `Tools → Settings → Engines → Add`, command = path to the binary,
protocol = UCI.

Command line example:

```bash
cutechess-cli -engine cmd=./babachess -engine cmd=<opponent> \
              -each proto=uci tc=60+0.6 -games 2 -rounds 1
```

### Lucas Chess (Windows)

`Competition → Engines… → New engine`, select the executable, protocol
**UCI**, then set the engine's strength/parameters in its properties.

### WinBoard / XBoard

Add to the engine list and select protocol **UCI**, or let it negotiate the
XBoard protocol. Example:

```bash
xboard -fcp ./babachess -fd . -scp ./babachess -sd . -tc 5 -inc 0.1
```

### Sanity check from a terminal

```bash
printf 'uci\nquit\n' | ./babachess        # prints id name BabaChess 1.4.0 ... uciok
./babachess --version                     # BabaChess 1.4.0
./babachess --selftest                    # 146 checks, all should pass
```

---

## UCI options

| Option | Type | Default | Notes |
|---|---|---|---|
| `Hash` | spin | 64 (MB) | **Inert**: the table size is compile-time. The option advertises the real size and warns if a different value is requested; a request clears the table. |
| `Threads` | spin | 1 | 1–16, Lazy SMP. |
| `OwnBook` | check | true | Use the Polyglot book if one is loaded. |
| `BookFile` | string | `books/book.bin` | Path to a Polyglot `.bin` book. |
| `SyzygyPath` | string | *(empty)* | Directory of Syzygy `.rtbw`/`.rtbz` files. When empty, the conventional locations are probed silently at startup (new in 1.4.0). |

Command-line options: `--threads N` (also `-TN`, `--thread=N`), `--book <file>`,
`--syzygy <dir>`, `--params <file>`, `--dump-params`, `--eval-fens <file>`,
`--bench [depth]`, `--perft <FEN> <depth>`, `--selftest`, `--version`.

---

## Known limitations

- **DTZ at the root is opt-in.** By default Syzygy probing is **WDL-only**: the
  engine knows a position is won/drawn/lost but not the distance-to-zero, and in
  the 50-move-rule zone it can miss a win a DTZ-aware engine would convert. The
  DTZ root probe (`S_SYZYGY_ROOT 1` in a `--params` file, with `.rtbz` tables
  present) fixes those conversions; it stays off by default.
- **Transposition table assumes the x86-64 memory model.** The lock-free shared
  TT relies on total-store-order behaviour (three `pragma Atomic`, no explicit
  barriers). It is **not portable** to weakly-ordered architectures such as ARM
  or POWER. This release is x86-64 only.
- **The `release` build requires BMI2/POPCNT.** See *CPU requirements* above.
- **PEXT is slow on AMD Zen 1/Zen 2**; use the `portable` build there.
- **Lazy SMP scaling flattens around 8 threads.** Beyond roughly 8 threads the
  additional helpers bring little extra strength.
- **Handcrafted, not NNUE.** The evaluation is a classical tapered handcrafted
  eval, tuned by Texel on self-play. King safety is a **known weak point**
  (several attempts to improve it measured negative; see
  `DEVELOPMENT_HISTORY.md` §17). Do not expect NNUE-level play.
- **Draws are still an evaluation problem, not a solved one.** 1.3.3 fixed the
  *scaling* of known drawn material configurations; 1.4.0 adds no general draw
  detector (no fortress or repetition-aware static eval).
- **No engine-strength limiter.** Unlike Stockfish, BabaChess has no
  `UCI_LimitStrength`/`UCI_Elo`; to weaken it, use your GUI's time handicap or
  reduce `Threads`.

---

## Playing strength (estimate)

No **absolute CCRL rating** is claimed.

**The search tree is unchanged from 1.3.3** (`--bench` node counts are
identical). The SEE inlining is a speed-up, not a strength change, and no Elo
gain is claimed for it.

**First anchored evaluation (new tooling in 1.4.0).** 800 games — 200 per
opponent, 100 with each colour — at `10+0.1`, bookless, over the opening suite,
against Stockfish `UCI_LimitStrength` + `UCI_Elo` at 1800 / 2200 / 2600 / 3000:

| Opponent | Anchor | n | W-D-L | Score | Implied Elo |
|---|---|---:|---|---:|---:|
| SF1800 | 1800 | 200 | 188-6-6 | 95.5 % | 2331 |
| SF2200 | 2200 | 200 | 163-7-30 | 83.2 % | 2479 |
| SF2600 | 2600 | 200 | 132-20-48 | 71.0 % | 2756 |
| SF3000 | 3000 | 200 | 9-33-158 | 12.8 % | 2666 |

Pooled maximum-likelihood estimate: **2655** (95 % CI **2618–2693**, SE 18.9).

**Read this carefully.** The per-anchor implied ratings spread from **2331 to
2756**, so Stockfish's `UCI_Elo` ladder is not perfectly consistent against
BabaChess (and/or there is a style effect). The statistical interval (±19)
therefore **understates** the real uncertainty: treat the absolute value as
**roughly 2600–2700 with a ±150–200 systematic margin**, not "2655 ± 19".
Compare runs made with the **same anchors**; this is not an official rating.
The raw games are archived in `pgn/`.

**Relative to 1.3.3**: no regression measured (the 1.3.3 evaluation fix itself
was +7.3 ± 13.1 Elo over 1 000 games at `1+0.1`, inconclusive).

**Relative to 1.2.0**: the 1.3.0 search lot adds roughly **+15 Elo** at fast time
controls (two independent 1 000-game seeds).

**Against GNU Chess 6.2.7** (60+1, 100 games, 50 balanced openings in both
colours, books off, one thread each): **48.5 / 100** — level (see
`DEVELOPMENT.md` §76).

---

## Documentation

- **`docs/`** — the general bilingual guide *How to build a chess engine*
  (English `*-en.md`, French `*-fr.md`); start at `docs/README-en.md` or
  `docs/README-fr.md`.
- **`src/doc/`** — the technical reference for this engine (French `*-fr.md`,
  English `*-en.md`).
- **`CONTRIBUTING.md` / `CONTRIBUTING-fr.md`** — build, test, measure, tune.

---

## Licence

**GPL-3.0-or-later** (see `LICENSE`), inherited from AdaChess. The Syzygy probe
(vendored Fathom) and its bundled `stdendian.h` are under the **MIT** licence
(see `NOTICE.md` and `src/fathom/LICENSE`). The bundled opening book is derived
from the Lichess standard rated database, released under **CC0**.
