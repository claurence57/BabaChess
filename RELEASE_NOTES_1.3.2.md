# BabaChess 1.3.2 — Release Notes

**BabaChess** is a chess engine written in **Ada 2012**, using a **bitboard**
board representation. It speaks **UCI** and **XBoard/Winboard** and runs on
64-bit **Windows** and **Linux**.

BabaChess is a fork of [AdaChess](https://github.com/adachess/AdaChess); see
`NOTICE.md` for provenance and licensing.

---

## What's in 1.3.2

**A documentation release. The engine is unchanged from 1.3.1** (`--bench 9` =
492 444 nodes, `--selftest` 146/146). This version aligns the archives with the
now **bilingual** documentation.

Also new:

- **Technical reference `src/doc/` is now bilingual**: every topic is available
  in French (`*-fr.md`) and English (`*-en.md`), and every reference to it was
  updated to the matching language.
- **`CONTRIBUTING-fr.md`**: French counterpart of `CONTRIBUTING.md`.
- **Documentation CI check** (`scripts/check_docs.py`): enforces French/English
  heading parity and valid internal links over `docs/` and `src/doc/`, run on
  every push.
- The archives now bundle the documentation in **both languages** (`docs/` and
  `src/doc/`), plus both READMEs and both CONTRIBUTING files.

**Engine summary (unchanged since 1.3.0)**: search lot — LMR regime, history
aging, PV flag, transposition table 16 → 64 MiB — worth **+15 Elo** (two
1 000-game seeds), plus cleanup and behaviour-preserving speedups.

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
- Only 64-bit x86 (x86-64) binaries are provided for 1.3.2. There is no
  32-bit, ARM or POWER build.

---

## Download

Pick **one** archive for your OS:

```
babachess-1.3.2-linux-x86_64-bmi2.tar.gz       Linux, modern Intel/AMD (BMI2+POPCNT)
babachess-1.3.2-linux-x86_64-portable.tar.gz   Linux, any x86-64
babachess-1.3.2-windows-x86_64-bmi2.zip        Windows, modern Intel/AMD
babachess-1.3.2-windows-x86_64-portable.zip    Windows, any x86-64
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
printf 'uci\nquit\n' | ./babachess        # prints id name BabaChess 1.3.2 ... uciok
./babachess --version                     # BabaChess 1.3.2
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
| `SyzygyPath` | string | *(empty)* | Directory of Syzygy `.rtbw`/`.rtbz` files; inert when empty. |

Command-line options: `--threads N` (also `-TN`, `--thread=N`), `--book <file>`,
`--syzygy <dir>`, `--params <file>`, `--dump-params`, `--eval-fens <file>`,
`--bench [depth]`, `--perft <FEN> <depth>`, `--selftest`, `--version`.

---

## Known limitations

- **DTZ at the root is opt-in.** By default Syzygy probing is **WDL-only**:
  the engine knows a position is won/drawn/lost but not the distance-to-zero,
  and in the 50-move-rule zone it can miss a win a DTZ-aware engine would
  convert. The DTZ root probe (`S_SYZYGY_ROOT 1` in a `--params` file, with
  `.rtbz` tables present) fixes those conversions; it stays off by default.
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
  `DEVELOPMENT_HISTORY.md` §17). Do not expect NNUE-level play.
- **No engine-strength limiter.** Unlike Stockfish, BabaChess has no
  `UCI_LimitStrength`/`UCI_Elo`; to weaken it, use your GUI's time handicap or
  reduce `Threads`.

---

## Playing strength (estimate)

No **absolute** rating is claimed. The engine is the same as 1.3.0.

**Relative to 1.2.0**: the search lot adds roughly **+15 Elo** at fast time
controls (1+0.1), measured by SPRT over two independent 1 000-game seeds
(+16.0 ± 14.1 and +14.3 ± 14.1; pooled +15.1 ± 10.0 over 2 000 games).

**Against GNU Chess 6.2.7** (60+1, 100 games, 50 balanced openings in both
colours, books off, one thread each): **48.5 / 100** — level. See
`DEVELOPMENT.md` §76.

**To weaken BabaChess** for play against humans, use your GUI's time handicap or
reduce `Threads`; there is no `UCI_LimitStrength`/`UCI_Elo` in this engine.

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
