# BabaChess 1.0.0 — Release Notes

**BabaChess** is a chess engine written in **Ada 2012**, using a **bitboard**
board representation. It speaks **UCI** and **XBoard/Winboard** and runs on
64-bit **Windows** and **Linux**.

BabaChess is a fork of [AdaChess](https://github.com/adachess/AdaChess); see
`NOTICE.md` for provenance and licensing.

---

## What's in 1.0.0

This is the **first public release**. It does not change the playing strength
of the prior development build: it freezes a functionally stable engine, gives
it a single version string, ships a ready-to-use opening book, hardens and
calibrates it, and adds release packaging.

- **Search**: principal-variation search (PVS) with aspiration windows,
  transposition table, move ordering (hash, MVV-LVA, killers, history,
  counter-move, continuation history), late-move reductions/pruning, check
  extensions, mate-distance pruning, bounded quiescence with SEE.
- **Evaluation**: tapered (middlegame/endgame) handcrafted evaluation. No NNUE.
- **Lazy SMP** multi-threading (shared transposition table, per-thread
  heuristics), up to 16 threads.
- **Polyglot** opening book (a generic CC0-derived book is bundled) and
  **Syzygy** endgame tablebases (WDL only; see limitations).
- **Integral self-test suite** (136 checks) and a fixed benchmark.
- **Single version constant**: UCI `id name`, XBoard `myname`, `--version`
  and the banner all report `BabaChess 1.0.0`.

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
- Only 64-bit x86 (x86-64) binaries are provided for 1.0.0. There is no
  32-bit, ARM or POWER build.

---

## Download

Pick **one** archive for your OS:

```
babachess-1.0.0-linux-x86_64-bmi2.tar.gz       Linux, modern Intel/AMD (BMI2+POPCNT)
babachess-1.0.0-linux-x86_64-portable.tar.gz   Linux, any x86-64
babachess-1.0.0-windows-x86_64-bmi2.zip        Windows, modern Intel/AMD
babachess-1.0.0-windows-x86_64-portable.zip    Windows, any x86-64
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
printf 'uci\nquit\n' | ./babachess        # prints id name BabaChess 1.0.0 ... uciok
./babachess --version                     # BabaChess 1.0.0
./babachess --selftest                    # 136 checks, all should pass
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

- **No DTZ at the root.** Syzygy probing is **WDL-only**: the engine knows a
  position is won/drawn/lost but without distance-to-zero at the root, so it may
  take a longer route in a won endgame. In the 50-move-rule zone this can mean
  missing a win that a DTZ-aware engine would find.
- **Transposition table assumes the x86-64 memory model.** The lock-free shared
  TT relies on total-store-order behaviour (three `pragma Atomic`, no explicit
  barriers). It is **not portable** to weakly-ordered architectures such as
  ARM or POWER. This release is x86-64 only.
- **The `release` build requires BMI2/POPCNT.** See *CPU requirements* above.
- **PEXT is slow on AMD Zen 1/Zen 2**; use the `portable` build there.
- **Lazy SMP scaling flattens around 8 threads.** Beyond roughly 8 threads the
  additional helpers bring little extra strength.
- **Handcrafted, not NNUE.** The evaluation is a classical tapered handcrafted
  eval. King safety is a **known weak point** (several attempts to improve it
  measured negative; see `DEVELOPMENT.md` §17). Do not expect NNUE-level play.
- **No engine-strength limiter.** Unlike Stockfish, BabaChess has no
  `UCI_LimitStrength`/`UCI_Elo`; to weaken it, use your GUI's time handicap or
  reduce `Threads`.

---

## Playing strength (estimate)

**Status: an honest relative Elo with an interval is reported here once the
release gauntlet has been run.** No absolute rating is invented here.

- A gauntlet of **≥ 1000 games** was played with the repository opening suite,
  book **neutralised**, against opponents of known level (see the release
  report / `DEVELOPMENT.md`).
- Any Elo figure published with this release is **relative to the tested
  opponents under the stated time control**, with its error bar; it is **not** a
  CCRL or FIDE rating.
- Absolute reference ratings of the opponents are quoted only if verified on
  the CCRL list at the matching time control; otherwise the report says so.

See the release report for the raw numbers (games, scores, intervals).

---

## Licence

**GPL-3.0-or-later** (see `LICENSE`), inherited from AdaChess. The Syzygy probe
(vendored Fathom) and its bundled `stdendian.h` are under the **MIT** licence
(see `NOTICE.md` and `src/fathom/LICENSE`). The bundled opening book is derived
from the Lichess standard rated database, released under **CC0**.
