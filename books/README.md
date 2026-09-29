# Bundled opening book — `book.bin`

`book.bin` is a generic Polyglot opening book shipped inside the BabaChess
1.0.0 release archives at `books/book.bin` (the location the engine probes by
default; see `BBChess.Protocol.Load_Default_Book`).

It is **not committed to git** — it is large and fully regenerable from a
public source. This directory only keeps this provenance note and the
generator. `.gitignore` ignores `books/*`.

## Provenance

| Field | Value |
|---|---|
| Source | Lichess standard rated database (CC0) |
| URL | `https://database.lichess.org/standard/lichess_db_standard_rated_2016-01.pgn.zst` |
| Month | 2016-01 |
| SHA256 (compressed source) | `faad7775d5da5c579eb7e5243bedd9a2c8c377362a7465988cd036238a3258d1` |
| Licence | CC0 (public domain dedication) — compatible with GPL-3.0-or-later |
| Generator | `scripts/make_book.py` (Python 3, `python-chess` 1.11.2) |
| SHA256 (`book.bin`) | `f917c95b84eb27d8d488b4ad35d3a529236d9ab205ab515e22a40043a3454e7d` |
| Size | 611 056 bytes = **38 191** entries (0.58 MiB) |

The Lichess database is released under **CC0**; the book is a **derived work**
(a statistical summary of move choices). It is recorded in `NOTICE.md`.

## Filters and parameters (exact)

```
scripts/make_book.py --month 2016-01 \
  --min-elo 2000 --max-ply 16 \
  --min-pos 5 --min-move 4 --min-move-share 1.0 --min-score 0.44 --max-moves 10
```

- **Games**: WhiteElo **and** BlackElo >= **2000**. The mission's preferred
  floor is 2200, but a single Lichess month only yields ~29 438 qualifying
  games at 2200 (too few for a stable book), versus **168 262** at 2000; the
  documented fallback to 2000 was therefore applied.
- **Excluded**: Bullet/UltraBullet (Blitz slow, Rapid and Classical kept),
  abandoned/unterminated games, non-standard variants.
- **Depth**: 16 plies maximum (the engine's probe limit).
- **Per (position, move)**: at least `min_pos=5` games through the position,
  `min_move=4` games on the move, the move >= 1% of that position's games,
  a mover's expected score >= 0.44, at most 10 moves kept.
- **Weight**: proportional to `games * score^2`, normalised per position into
  `[1, 65535]`, never 0 (strict Polyglot format: u64 key, u16 move, u16
  weight, u32 learn=0; sorted by unsigned key).
- **Stockfish pruning**: **step not run** (no Stockfish binary supplied at
  generation time). The `--stockfish PATH --depth 12` step is available.

### Why the defaults differ from the first draft

The mission suggested defaults (`min_pos=40`, `min_move=12`, share 3%,
max 6 moves) produce only ~1 417 entries from 2200+ games and **fail the
required coverage test**: `e2e4 g8f6` is only the **7th** most-played reply
after 1.e4 (cut by "at most 6 moves"), while `d2d4 e7e5` (1.0%), `d2d4 c7c6`
(2.4%) and `d2d4 e7e6` (expected score 0.4497) all fall below the stricter
thresholds. The calibrated values above are the smallest change that satisfies
the coverage criterion while keeping the book modest (38 191 entries, well
under the "few MB" ceiling).

## Regenerating

```bash
pip install chess==1.11.2
scripts/make_book.py --month 2016-01 --min-elo 2000 \
  --sha256 faad7775d5da5c579eb7e5243bedd9a2c8c377362a7465988cd036238a3258d1 \
  --out books/book.bin
```

## Validation

```bash
scripts/make_book.py --validate books/book.bin
```

Checks: (a) size multiple of 16 and keys sorted; (b) depth-first tree walk
from the initial position with the `python-chess` reader; (c) minimal
coverage (1.e4/1.d4/1.Nf3/1.c4 present, and a reply to e5/c5/e6/c6/d5/Nf6
after 1.e4 and 1.d4).
