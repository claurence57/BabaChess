# Building BabaChess and CPU optimization

This document describes the **compilation instructions** actually used and
the **history of CPU optimizations** (the engine's proven strength lever).

## Makefile (CPU selection)

A `Makefile` (root) wraps `gprbuild`, in the spirit of RubiChess's: it
**detects the host CPU** and chooses the ISA switches, then injects them via
the project external `BABA_ARCH_FLAGS` (no flag hard-coded).

```bash
make                 # release, ISA auto-detected
make checked         # release speed, run-time checks active (SPRT mode)
make portable        # generic x86-64 (software PEXT fallback)
make debug           # assertions + warnings
make ARCH=native     # force -march=native
make ARCH=v3         # force an x86-64 level (v1..v4)
make ARCH=skylake    # force any -march= name
make ARCH=generic    # no ISA switch (the .gpr default)
make test            # release + --selftest
make bench [DEPTH=9] # release + --bench
make info            # detected CPU and chosen switches
make clean
```

### Why `x86-64-vN` levels and not `-march=native`

The Makefile **does not use** `-march=native` by default. `--bench 11`
measurements (25 paired runs, min/median) on the development CPU (Xeon E3-1270
v6, Kaby Lake):

| Variant | min (s) | median (s) |
|---|---|---|
| `.gpr` default (POPCNT/BMI/BMI2, `-mtune=generic`) | 0.4370 | 0.4577 |
| **`-march=x86-64-v3`** | **0.4298** | **0.4528** |
| `-mavx2` alone | 0.4283 | 0.4550 |
| **`-march=native`** (= `-mtune=skylake`) | 0.4481 | **0.4745** |

`-march=native` **slows things down by about 2.5%**: it also sets
`-mtune=<that CPU>`, and `-mtune=skylake` is worse here than
`-mtune=generic`. The **`x86-64-vN` levels** (which keep
`-mtune=generic`) are neutral to slightly positive. Hence the choice: detect
the best supported level and pass it as `-march`.

The added instruction sets (`AVX2`, `FMA`, `LZCNT`, `ADX` in v3) **do not
change the search tree**: `--bench 9` = **518 612 nodes** in every
case; this is a **speed** lever, not strength directly.

> **PGO not retained.** A `-fprofile-generate`/`-fprofile-use` pass was
> tried (doable with `-cargs`/`-largs`), but measured **slower**
> (0.4955 s versus 0.4441 s in `--bench 11`) and fragile with `-flto`: the
> Makefile does **not** offer it.
>
> **Reproduction (2026-10-12)**: as the repository offered no target, the test was
> redone by hand with an **explicit profile directory**
> (`-fprofile-generate/use=DIR`, so that `rm -rf obj/` does not lose the
> `.gcda`) and a profile taken on `--bench` 9/11/12, ten repetitions, min (same
> dev CPU: Xeon E3-1270 v6). Still **slower**, with *and* without LTO:
>
> | Variant | bench 9 | bench 11 | bench 12 |
> |---|---|---|---|
> | `release` (LTO) | 0.247 | 0.538 | 1.103 |
> | `release` `-fno-lto` | 0.236 | 0.539 | 1.108 |
> | `release` **+ PGO** | 0.259 | 0.581 | 1.165 |
> | `-fno-lto` **+ PGO** | 0.266 | 0.575 | 1.138 |
>
> That is **+3 to +12%** time depending on depth; nodes **identical**
> (`--selftest` 145/145). `-O3 -gnatN` is already aggressive for this code and
> PGO degrades block layout, so **PGO stays out**: it is not a
> measurement artefact but a real regression on this base.

## Build modes

`babachess.gpr` exposes the `Mode` scenario (`release` by default, `debug`,
`portable`, `checked`). The binary is written to `bin/babachess`.

```bash
gprbuild -P babachess.gpr -XMode=release    # default: POPCNT/BMI2/PEXT, -flto
gprbuild -P babachess.gpr -XMode=checked    # release speed + active checks (SPRT)
gprbuild -P babachess.gpr -XMode=portable   # any x86-64, software PEXT fallback
gprbuild -P babachess.gpr -XMode=debug      # assertions (-gnata), without -gnatp
```

The Makefile only chooses `Mode` and `BABA_ARCH_FLAGS`; the switches
below remain the reference.

### Exact switches (GNAT + C)

| Mode | Ada (`Switches ("ada")`) | C (`Switches ("c")`) |
|---|---|---|
| **release** | `-gnat2012 -gnatp -gnatN -O3 -gnatf -gnatep=../src/prep.data -gnateDREL -mpopcnt -mbmi -mbmi2 -flto` | `-O3 -mpopcnt -mbmi -mbmi2` |
| **checked** | `-gnat2012 -gnata -gnatN -O3 -gnatf -gnatep=../src/prep.data -gnateDREL -mpopcnt -mbmi -mbmi2 -flto` | `-O3 -mpopcnt -mbmi -mbmi2` |
| **portable** | `-gnat2012 -gnatp -gnatN -O3 -gnatf -gnatep=../src/prep.data` | `-O3` |
| **debug** | `-gnat2012 -gnata -g -gnatep=../src/prep.data` | `-O0 -g` |

Each mode additionally receives `$(BABA_ARCH_FLAGS)` (external, empty by
default), which the Makefile uses to add the CPU ISA switch (`-march=x86-64-v3`,
`-march=native`, …).

- `-gnatep=../src/prep.data` + `-gnateDREL`: GNAT's **integrated preprocessor**.
  `prep.data` opens the session with `* -u` (undefined symbols = false); `REL`
  is defined only in `release`/`checked`, so `#if REL` selects the
  BMI2 **PEXT** intrinsic, `#else` the software fallback.
- `-gnatp` removes the run-time checks (`release`/`portable`) → every access
  to buffers must be explicitly bounded (`BBChess.Text`).
- `-flto` (Ada, `release` and `checked`): inter-unit link-time optimization. **Not
  on the C side**: gprbuild archives the C objects with `ar` and links
  `libbabachess.a`, yet the standard FSF gprbuild does not use `gcc-ar`, so an
  LTO bytecode archive makes the link fail (`lto1: bytecode stream ... LTO
  version ...`); the C is not on the hot path.
- **`checked`**: `release` speed (`-O3 -gnatN -flto`) **with** the
  run-time checks (`-gnata`, without `-gnatp`). Measured **≈ 11% slower**
  than `release` (`--bench 11`, median), nodes **identical**. It is the mode for
  **long SPRT campaigns**; `release` remains the distribution mode.
- **portable** removes `-mpopcnt/-mbmi/-mbmi2/-flto` and leaves `REL` undefined:
  it runs on **any x86-64**, with the software PEXT fallback of `bbchess-bits.c`
  (≈ 25% slower). It is the mode to distribute for an older CPU.
- **Gotcha**: all modes share `obj/`. After building another mode, run
  `rm -rf obj` before rebuilding (and never compare
  `--bench` between two modes without a clean rebuild).

### Thread count aliases

The Lazy SMP thread count (1 to 16) is set interchangeably by:

```bash
bin/babachess --threads 4      # separate argument
bin/babachess -T4              # short form
bin/babachess --thread=4       # long form
```

The `-T#` / `--thread=#` forms are parsed by `BBChess.Text.Thread_Count`
(tested in `--selftest`); any malformed value falls back to 1. In UCI,
`setoption name Threads value N` remains the equivalent.

## History of CPU optimizations

Seven "behaviour-preserving" passes: the fixed-depth search tree is
**bit-identical** (same `--bench` nodes), only the speed increases. Full
detail in `DEVELOPMENT.md` (§25, §30-31, §33, §36-37, §46).

| Pass | Main changes | Measured gain |
|---|---|---|
| 1 (§25) | PEXT inlined (GNAT preprocessor), `Make_Move`/movegen, eval | **×1.59** speed |
| 2 (§30) | PEXT inlined, make/movegen, eval | −11.9% instructions |
| 3 (§31) | king path first (movegen), SEE bitboard-only, eval | −12.2% instructions |
| 4 (§33) | TT prefetch, king/pawn safety bitboard, hoists | −6.9% instructions (×1.08) |
| 5 (§36) | removal of the `Tac` table, merged `Move_Piece`, `-flto` | −3.1% instructions, −3.9% cycles |
| 6 (§37) | TT entry 32 → 24 bytes | −2.3% cycles (×1.02) |
| 7 (§46) | `Poll_Time` split, check test avoided, `Suppress_Initialization` | −0.81% instructions, −1.47% cycles |

**Cumulative**: ≈ **×2.3** speed (`--bench 11`: ~1 360 → ~3 170 knps; bench 9
0.56 → 0.25 s). A "capstone" SPRT (300 games, 1+0.1) between the current engine
and the pre-optimization baseline is worth **+123 ± 31.6 Elo** (LOS 100%), the only
**demonstrated** strength lever of the engine (§32).

## State: no more easy gain, but not "nothing to gain"

All **safe** micro-optimizations (bit-identical tree) have been
tried; the latest passes yield **< 1%** and the returns decrease
clearly. The profile is still dominated by `Negamax` (~39%, **memory latency** of the
transposition table), `Positional_Score` (~19%) and `Generate_Legal_Common`
(~18%). The remaining leads are **non-trivial and risky**:

- **incremental evaluation** (update the eval terms in
  `Make_Move`/`Unmake_Move`), the only real structural reserve;
- **deep TT reorganization** (access, buckets): would change the entries
  accepted, hence the tree.

These leads require **proving identity** (`--bench` nodes + byte-identical eval
over thousands of positions) and a **long SPRT** (≥ 600-1 000
games) before any adoption. The remaining micro-adjustments yield too
little to be distinguishable from noise.
