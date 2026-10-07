# BabaChess 1.2.0 — Release Notes

**BabaChess** is a chess engine written in **Ada 2012**, using a **bitboard**
board representation. It speaks **UCI** and **XBoard/Winboard** and runs on
64-bit **Windows** and **Linux**.

BabaChess is a fork of [AdaChess](https://github.com/adachess/AdaChess); see
`NOTICE.md` for provenance and licensing.

---

## What's in 1.2.0

**A large playing-strength release.** Every change below was measured with
sequential tests (SPRT, 1 000 games per test, both colours over a balanced
opening suite), and each retained gain was confirmed by a second independent
series or by a formal SPRT PASS. Details are in `DEVELOPMENT.md` §70-§78.

| Change | Measured gain vs the previous build |
|---|---|
| **Evaluation tuned with Texel on self-play** (274 parameters: scalars, piece-square tables, passed-pawn tables; 670 679 quiet positions from 56 576 self-play games) | **+104 / +131 Elo** |
| **Search**: SEE-losing captures ordered after quiet moves, gradual aspiration-window widening, transposition table in quiescence, reverse futility pruning up to depth 6 | **+93 Elo** |
| **Passed pawns**: king proximity to the stop square, blocked passers, rear pawn of a doubled passer | **+30 Elo** |
| **Mobility area** (squares attacked by enemy pawns no longer count) | **+18 / +31 Elo** |

Also new:

- **Syzygy DTZ root probe** (`S_SYZYGY_ROOT 1` through `--params`), **off by
  default**: in the 50-move zone of a tablebase win the engine plays the
  DTZ-optimal move (verified 6/6 against an independent reader).
- **Texel tooling**: `scripts/texel_extract.py` and `scripts/texel.py`; the
  piece-square and passed-pawn tables are now tunable through `--params`.
- Self-test suite: **145 checks**.
- All reported names say `BabaChess 1.2.0` (UCI `id name`, XBoard `myname`,
  `--version`, banner).

Measured **without** gain and left disabled or unmerged: endgame scaling,
hanging-piece threats, connected/backward pawns, king-safety phase ramp, IIR,
history-based LMR, eval-gated null move, best-move-stability time management, a
second Texel pass, correction history.

Unchanged from 1.0.0: UCI + XBoard, Lazy SMP (up to 16 threads), bundled
Polyglot book, Syzygy WDL probing, handcrafted evaluation (no NNUE).

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
- Only 64-bit x86 (x86-64) binaries are provided for 1.2.0. There is no
  32-bit, ARM or POWER build.

---

## Download

Pick **one** archive for your OS:

```
babachess-1.2.0-linux-x86_64-bmi2.tar.gz       Linux, modern Intel/AMD (BMI2+POPCNT)
babachess-1.2.0-linux-x86_64-portable.tar.gz   Linux, any x86-64
babachess-1.2.0-windows-x86_64-bmi2.zip        Windows, modern Intel/AMD
babachess-1.2.0-windows-x86_64-portable.zip    Windows, any x86-64
```

Verify integrity against the `SHA256SUMS` file published with the release.

Each archive contains: the engine binary, `LICENSE`, `NOTICE.md`, the Fathom
MIT licence (`src/fathom/LICENSE`), `README.md`, these release notes, and the
bundled book at `books/book.bin`.

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
printf 'uci\nquit\n' | ./babachess        # prints id name BabaChess 1.2.0 ... uciok
./babachess --version                     # BabaChess 1.2.0
./babachess --selftest                    # 145 checks, all should pass
```

---

## UCI options

| Option | Type | Default | Notes |
|---|---|---|---|
| `Hash` | spin | 16 (MB) | **Inert**: the table size is compile-time. The option advertises the real size and warns if a different value is requested; a request clears the table. |
| `Threads` | spin | 1 | 1–16, Lazy SMP. |
| `OwnBook` | check | true | Use the Polyglot book if one is loaded. |
| `BookFile` | string | `books/book.bin` | Path to a Polyglot `.bin` book. |
| `SyzygyPath` | string | *(empty)* | Directory of Syzygy `.rtbw`/`.rtbz` files; inert when empty. |

Command-line options: `--threads N` (also `-TN`, `--thread=N`), `--book <file>`,
`--syzygy <dir>`, `--params <file>`, `--dump-params`, `--eval-fens <file>`,
`--bench [depth]`, `--perft <FEN> <depth>`, `--selftest`, `--version`.

---

## Known limitations

- **DTZ at the root is opt-in.** By default Syzygy probing is **WDL-only**:
  the engine knows a position is won/drawn/lost but not the distance-to-zero,
  and in the 50-move-rule zone it can miss a win a DTZ-aware engine would
  convert (measured on KBNvK, KQvKR, KRPvKR). Since 1.2.0, enabling the DTZ
  root probe (`S_SYZYGY_ROOT 1` in a `--params` file, with `.rtbz` tables
  present) fixes those conversions; it stays off by default.
- **Transposition table assumes the x86-64 memory model.** The lock-free shared
  TT relies on total-store-order behaviour (three `pragma Atomic`, no explicit
  barriers). It is **not portable** to weakly-ordered architectures such as
  ARM or POWER. This release is x86-64 only.
- **The `release` build requires BMI2/POPCNT.** See *CPU requirements* above.
- **PEXT is slow on AMD Zen 1/Zen 2**; use the `portable` build there.
- **Lazy SMP scaling flattens around 8 threads.** Beyond roughly 8 threads the
  additional helpers bring little extra strength.
- **Handcrafted, not NNUE.** The evaluation is a classical tapered handcrafted
  eval, tuned by Texel on self-play. King safety is a **known weak point**
  (several attempts to improve it measured negative; see
  `DEVELOPMENT_HISTORY.md` §17 and `DEVELOPMENT.md` §73). Do not expect NNUE-level play.
- **No engine-strength limiter.** Unlike Stockfish, BabaChess has no
  `UCI_LimitStrength`/`UCI_Elo`; to weaken it, use your GUI's time handicap or
  reduce `Threads`.

---

## Playing strength (estimate)

No **absolute** rating is claimed.

**Against GNU Chess 6.2.7** (1.2.0, 60+1, 100 games, 50 balanced openings in
both colours, books off, one thread each): **48.5 / 100** (23 wins, 26 losses,
51 draws), i.e. **−10 ± 50 Elo: level**. GNU Chess crashed four times; each time
BabaChess was winning on the board, so the score is not inflated. For
comparison, earlier versions scored 0-8-2 and then 1-13-6 against the same
opponent. See `DEVELOPMENT.md` §76.

**Relative to 1.0.0**: the self-play gains listed above add up to roughly
**+200 Elo or more** at fast time controls (4+0.04). They were measured
step by step against the previous build, not 1.2.0 directly against 1.0.0, so
the total is an order of magnitude, not an exact figure.

The 1.0.0 calibration against Stockfish `UCI_Elo` 1900-2300 (≈ 2 185-2 440,
indicative only) was **not re-run** for 1.2.0; given the gains above, 1.2.0
should rate well above those 1.0.0 figures.

**To weaken BabaChess** for play against humans, use your GUI's time handicap or
reduce `Threads`; there is no `UCI_LimitStrength`/`UCI_Elo` in this engine.

---

## Licence

**GPL-3.0-or-later** (see `LICENSE`), inherited from AdaChess. The Syzygy probe
(vendored Fathom) and its bundled `stdendian.h` are under the **MIT** licence
(see `NOTICE.md` and `src/fathom/LICENSE`). The bundled opening book is derived
from the Lichess standard rated database, released under **CC0**.
