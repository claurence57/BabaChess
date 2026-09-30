#!/usr/bin/env python3
"""Build a generic, modest-size Polyglot opening book for BabaChess.

Source: one month of the Lichess standard rated database (CC0,
https://database.lichess.org). The month/URL/SHA256 of the downloaded source
are recorded so the book is reproducible. `.pgn.zst` is streamed through
`zstd -dc` (same approach as scripts/gen_dataset.py) so the decompressed PGN
is never written to disk.

The book is a set of 16-byte big-endian Polyglot entries:

    u64 key | u16 move | u16 weight | u32 learn(=0)

sorted by unsigned key. The move encoding is the Polyglot one (to_file bits
0-2, to_row 3-5, from_file 6-8, from_row 9-11, promotion 12-14; castling is
encoded "king takes rook"). Keys come from chess.polyglot.zobrist_hash and are
cross-checked against the values the engine already validates in --selftest.

Usage
-----
  # download + build (recommended; records month/URL/sha256)
  scripts/make_book.py --month 2016-01 --out books/babachess-book.bin

  # build from a local .pgn.zst (no download)
  scripts/make_book.py --pgn /tmp/lichess_db_standard_rated_2016-01.pgn.zst \
                       --out books/babachess-book.bin

  # optional: drop dubious moves with Stockfish
  scripts/make_book.py --month 2016-01 --out books/babachess-book.bin \
                       --stockfish /usr/games/stockfish --depth 12

  # validate an existing book (size/order, tree walk, minimal coverage)
  scripts/make_book.py --validate books/babachess-book.bin

Requires python-chess (`pip install chess`).
"""

from __future__ import annotations

import argparse
import hashlib
import io
import os
import struct
import subprocess
import sys
import urllib.request
from pathlib import Path

import chess
import chess.pgn
import chess.polyglot

ROOT = Path(__file__).resolve().parent.parent
LICHESS_BASE = "https://database.lichess.org/standard"
MAX_PLY = 16                       # engine probes the book only up to ply 16
NORMAL_TERMINATIONS = {"1-0", "0-1", "1/2-1/2"}
EXCLUDED_SPEEDS = {"bullet", "ultrabullet"}   # keep blitz (slow), rapid, classical

# Promotion letters -> Polyglot code (0 none, 1 knight, 2 bishop, 3 rook, 4 queen).
PROMO_CODE = {None: 0, chess.KNIGHT: 1, chess.BISHOP: 2, chess.ROOK: 3,
              chess.QUEEN: 4}


# --------------------------------------------------------------------------
#  Source handling
# --------------------------------------------------------------------------

def month_url(month: str) -> str:
    return f"{LICHESS_BASE}/lichess_db_standard_rated_{month}.pgn.zst"


def download(url: str, dest: Path, expected_sha: str | None = None) -> str:
    """Download url to dest, returning its SHA256. Verifies against
    expected_sha when given. Streams to a .part file then renames."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_suffix(dest.suffix + ".part")
    h = hashlib.sha256()
    total = 0
    print(f"downloading {url}", file=sys.stderr)
    with urllib.request.urlopen(url) as resp, open(part, "wb") as out:
        length = resp.headers.get("Content-Length")
        length = int(length) if length else 0
        while True:
            chunk = resp.read(1 << 20)
            if not chunk:
                break
            out.write(chunk)
            h.update(chunk)
            total += len(chunk)
            if length:
                pct = 100.0 * total / length
                print(f"\r  {total/1e6:8.1f} / {length/1e6:.1f} MB ({pct:5.1f}%)",
                      end="", file=sys.stderr)
    print(file=sys.stderr)
    sha = h.hexdigest()
    if expected_sha and sha != expected_sha:
        raise SystemExit(f"sha256 mismatch: got {sha}, expected {expected_sha}")
    part.replace(dest)
    return sha


def open_pgn(path: Path):
    """Stream a .pgn or .pgn.zst as bytes (decompressed on the fly)."""
    if str(path).endswith(".zst"):
        proc = subprocess.Popen(
            ["zstd", "-dc", str(path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        return proc.stdout
    return open(path, "rb")


# --------------------------------------------------------------------------
#  Polyglot move encoding
# --------------------------------------------------------------------------

def polyglot_move(board: chess.Board, move: chess.Move) -> int:
    """Encode a python-chess move in the Polyglot 16-bit format."""
    if board.is_castling(move):
        # Polyglot encodes castling as "king takes its own rook".
        rook_sq = (chess.H1 if board.turn == chess.WHITE else chess.H8) \
            if board.is_kingside_castling(move) \
            else (chess.A1 if board.turn == chess.WHITE else chess.A8)
        return encode_squares(move.from_square, rook_sq, 0)
    return encode_squares(move.from_square, move.to_square,
                          PROMO_CODE.get(move.promotion))


def encode_squares(frm: int, to: int, promo: int) -> int:
    return ((to & 7) | ((to >> 3) << 3)
            | ((frm & 7) << 6) | ((frm >> 3) << 9)
            | (promo << 12))


# --------------------------------------------------------------------------
#  Accumulation
# --------------------------------------------------------------------------

class Stats:
    """Per-(position, move) game count and score from the mover's point of
    view. A game contributes 1 to exactly one move of each position it
    passes through, so the sum of move counts of a position is the number of
    games that reached it."""

    __slots__ = ("moves",)

    def __init__(self) -> None:
        # key -> {move_uci: [n_games, score_white_relative]}
        self.moves: dict[int, dict[str, list[int]]] = {}

    def add(self, key: int, code: int, mover_white: bool, white_pts: float) -> None:
        pts = white_pts if mover_white else 1.0 - white_pts
        bucket = self.moves.setdefault(key, {})
        e = bucket.get(code)
        if e is None:
            bucket[code] = [1, int(round(pts * 2))]
        else:
            e[0] += 1
            e[1] += int(round(pts * 2))


def _iter_games_fast(byte_stream):
    """Yield (headers_text, movetext_bytes) games without building
    python-chess Game objects.

    python-chess tokenises the whole movetext (annotations, comments,
    variations) for every game, which dominates the runtime on a full month
    (tens of GB of decompressed PGN). We only need the headers to filter and
    then the mainline, and the Lichess PGNs are clean, so we split the stream
    on the blank line after the header block and parse the mainline lazily.
    """
    headers = []
    for raw in byte_stream:
        line = raw.rstrip(b"\r\n")
        if line.startswith(b"[") and line.endswith(b"]"):
            headers.append(line)
            continue
        if not line:
            if headers:
                movetext = []
                for follow in byte_stream:
                    s = follow.rstrip(b"\r\n")
                    if not s:
                        break
                    movetext.append(s)
                yield headers, b" ".join(movetext)
                headers = []
            continue
        headers = []


def parse_headers(header_lines) -> dict:
    out = {}
    for ln in header_lines:
        try:
            text = ln.decode("utf-8", "replace")
        except Exception:  # noqa: BLE001
            continue
        if text.startswith("[") and text.endswith("]"):
            key, _, rest = text[1:-1].partition(" ")
            rest = rest.strip()
            if rest.startswith('"') and rest.endswith('"'):
                out[key] = rest[1:-1]
    return out


def collect_games(args, byte_stream, stats: Stats) -> dict:
    """Read games, accumulate stats, return counters."""
    pts = {"1-0": 1.0, "0-1": 0.0, "1/2-1/2": 0.5}
    seen = qualifying = plies_done = 0
    for header_lines, movetext in _iter_games_fast(byte_stream):
        seen += 1
        if args.max_games and seen > args.max_games:
            break
        h = parse_headers(header_lines)
        if not headers_usable(h, args.min_elo):
            continue
        qualifying += 1
        result = h.get("Result", "*")
        board = chess.Board()
        ply = 0
        try:
            game = chess.pgn.read_game(io.StringIO(movetext.decode("utf-8", "replace")))
        except Exception:  # noqa: BLE001
            continue
        for move in game.mainline_moves():
            ply += 1
            if ply > args.max_ply:
                break
            key = chess.polyglot.zobrist_hash(board)
            code = polyglot_move(board, move)
            stats.add(key, code, board.turn == chess.WHITE, pts[result])
            board.push(move)
            plies_done += 1
    return {"seen": seen, "qualifying": qualifying, "plies": plies_done}


def headers_usable(h: dict, min_elo: int) -> bool:
    try:
        white = int(h.get("WhiteElo", "0"))
        black = int(h.get("BlackElo", "0"))
    except ValueError:
        return False
    if white < min_elo or black < min_elo:
        return False
    if h.get("Result", "*") not in NORMAL_TERMINATIONS:
        return False
    if h.get("Termination", "") in ("Abandoned", "Rules infraction", "Unterminated"):
        return False
    speed = h.get("Event", "").lower()
    if any(s in speed for s in EXCLUDED_SPEEDS):
        return False
    variant = h.get("Variant")
    if variant and variant.lower() != "standard":
        return False
    # Lichess sets "TimeControl" as "base+inc"; keep blitz (slow), rapid,
    # classical and drop bullet/ultrabullet even when the Event tag is odd.
    tc = h.get("TimeControl", "")
    if "+" in tc:
        try:
            base = int(tc.split("+")[0])
            if base <= 60 and int(tc.split("+")[1]) <= 1:
                return False
        except ValueError:
            pass
    return True


# --------------------------------------------------------------------------
#  Selection + weights
# --------------------------------------------------------------------------

def select_entries(stats: Stats, args) -> list[tuple[int, int, int]]:
    """Return (key, polyglot_move, weight) entries, one per retained move."""
    entries: list[tuple[int, int, int]] = []
    for key, bucket in stats.moves.items():
        total = sum(n for n, _ in bucket.values())
        if total < args.min_pos:
            continue
        cand = []
        for code, (n, halves) in bucket.items():
            if n < args.min_move:
                continue
            if 100.0 * n / total < args.min_move_share:
                continue
            score = halves / (2.0 * n)
            if score < args.min_score:
                continue
            cand.append((n, score, code))
        if not cand:
            continue
        cand.sort(key=lambda t: t[1] * t[2] * t[0], reverse=True)
        cand = cand[:args.max_moves]
        raw = [n * (score ** 2) for n, score, _ in cand]
        mx = max(raw)
        mn = min(raw)
        for (n, score, code), r in zip(cand, raw):
            if mx == mn:
                w = 65535
            else:
                w = 1 + int(round((r - mn) / (mx - mn) * 65534))
            entries.append((key, code, max(1, min(65535, w))))
    entries.sort(key=lambda e: e[0])
    return entries


# --------------------------------------------------------------------------
#  Write
# --------------------------------------------------------------------------

def write_book(path: Path, entries: list[tuple[int, int, int]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as f:
        for key, mv, w in entries:
            f.write(struct.pack(">QHHI", key, mv, w, 0))


# --------------------------------------------------------------------------
#  Optional Stockfish pruning
# --------------------------------------------------------------------------

def stockfish_prune(path: Path, stockfish: str, depth: int, drop_cp: int,
                    bad_cp: int) -> dict:
    """Drop book moves that Stockfish dislikes (mover's point of view):
    moves more than `drop_cp` worse than the best, or worse than `bad_cp`
    absolute. Rewrites the book in place. Returns counters."""
    eng = chess.engine.SimpleEngine.popen_uci(stockfish)
    eng.configure({"Threads": 1})
    entries = read_entries(path)
    kept: list[tuple[int, int, int]] = []
    removed = 0
    for key, mv, w in entries:
        board = board_for_key(key)     # reconstruct position from the tree
        if board is None:
            kept.append((key, mv, w))
            continue
        legal = encode_move_map(board)
        bmv = legal.get(mv)
        if bmv is None:
            kept.append((key, mv, w))
            continue
        info = eng.analyse(board, chess.engine.Limit(depth=depth))
        best = info["pv"][0] if info.get("pv") else None
        if best is None:
            kept.append((key, mv, w))
            continue
        score = info["score"].pov(board.turn).score(mate_score=100000) / 100.0
        # Re-search after playing the book move to get the mover's eval.
        after = board.copy()
        after.push(bmv)
        info2 = eng.analyse(after, chess.engine.Limit(depth=depth))
        score_mv = -info2["score"].pov(after.turn).score(mate_score=100000) / 100.0
        if score_mv < -bad_cp or (score - score_mv) > drop_cp:
            removed += 1
            continue
        kept.append((key, mv, w))
    eng.quit()
    kept.sort(key=lambda e: e[0])
    write_book(path, kept)
    return {"kept": len(kept), "removed": removed}


def board_for_key(key: int) -> chess.Board | None:
    """Reconstruct the position with the given Polyglot key by walking the
    book tree from the start position. Cheap enough for validation and the
    optional Stockfish pass when the book is modest."""
    return _POS_INDEX.get(key)


_POS_INDEX: dict[int, chess.Board] = {}


def build_pos_index(entries: list[tuple[int, int, int]]) -> None:
    """Map every book key to its board by BFS from the start position."""
    global _POS_INDEX
    _POS_INDEX = {}
    if not entries:
        return
    by_key = {}
    for key, mv, _ in entries:
        by_key.setdefault(key, []).append(mv)
    start = chess.Board()
    _POS_INDEX[chess.polyglot.zobrist_hash(start)] = start
    queue = [start]
    while queue:
        board = queue.pop()
        for mv in _decoded_moves(board, by_key.get(chess.polyglot.zobrist_hash(board), [])):
            if not board.is_legal(mv):
                continue
            child = board.copy()
            child.push(mv)
            ck = chess.polyglot.zobrist_hash(child)
            if ck not in _POS_INDEX:
                _POS_INDEX[ck] = child
                queue.append(child)


def encode_move_map(board: chess.Board) -> dict[int, chess.Move]:
    return {polyglot_move(board, m): m for m in board.legal_moves}


def _decoded_moves(board: chess.Board, encoded: list[int]) -> list[chess.Move]:
    out = []
    for e in encoded:
        for mv in board.legal_moves:
            if polyglot_move(board, mv) == e:
                out.append(mv)
                break
    return out


def save_stats_cache(path: Path, stats: "Stats", counters: dict) -> None:
    import json
    data = {
        "counters": counters,
        "moves": {str(k): {str(m): v for m, v in b.items()}
                  for k, b in stats.moves.items()},
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data))


def load_stats_cache(path: Path) -> tuple[dict, dict]:
    import json
    data = json.loads(path.read_text())
    moves = {int(k): {int(m): v for m, v in b.items()}
             for k, b in data["moves"].items()}
    return moves, data["counters"]


def read_entries(path: Path) -> list[tuple[int, int, int]]:
    data = path.read_bytes()
    if len(data) % 16:
        raise SystemExit(f"{path}: size {len(data)} is not a multiple of 16")
    out = []
    for i in range(0, len(data), 16):
        k, m, w, _learn = struct.unpack(">QHHI", data[i:i + 16])
        out.append((k, m, w))
    return out


# --------------------------------------------------------------------------
#  Validation
# --------------------------------------------------------------------------

def validate(path: Path) -> int:
    print(f"== validating {path} ==")
    data = path.read_bytes()
    ok = True

    # (a) size multiple of 16, keys strictly increasing (unsigned).
    if len(data) % 16 != 0:
        print(f"FAIL: size {len(data)} not a multiple of 16")
        return 1
    keys = [struct.unpack(">Q", data[i:i + 8])[0] for i in range(0, len(data), 16)]
    if any(keys[i] > keys[i + 1] for i in range(len(keys) - 1)):
        print("FAIL: keys are not sorted")
        ok = False
    print(f"(a) size {len(data)} bytes = {len(keys)} entries; "
          f"sorted={keys == sorted(keys)} ok")

    # (b) depth-first walk with python-chess' reader.
    reader = chess.polyglot.open_reader(str(path))
    per_ply: list[int] = []
    seen: set[int] = set()
    legal_counts: list[int] = []

    def walk(board: chess.Board, ply: int) -> None:
        key = chess.polyglot.zobrist_hash(board)
        if key in seen or ply > MAX_PLY:
            return
        seen.add(key)
        if ply >= len(per_ply):
            per_ply.append(0)
        per_ply[ply] += 1
        legal_counts.append(board.legal_moves.count())
        for entry in reader.find_all(board):
            child = board.copy()
            child.push(entry.move)
            walk(child, ply + 1)

    walk(chess.Board(), 0)
    reader.close()
    print(f"(b) book tree: {len(seen)} distinct positions reachable; "
          f"positions per ply = {per_ply[:MAX_PLY]}")
    if legal_counts:
        print(f"    branching: mean {sum(legal_counts)/len(legal_counts):.1f} "
              f"legal moves per node "
              f"(max {max(legal_counts)})")

    # (c) minimal coverage.
    missing = []
    for first in ["e2e4", "d2d4", "g1f3", "c2c4"]:
        r = chess.polyglot.open_reader(str(path))
        if not any(e.move == chess.Move.from_uci(first)
                   for e in r.find_all(chess.Board())):
            missing.append(first)
        r.close()
    for first in ["e2e4", "d2d4"]:
        for reply in ["e7e5", "c7c5", "e7e6", "c7c6", "d7d5", "g8f6"]:
            b = chess.Board()
            b.push(chess.Move.from_uci(first))
            r = chess.polyglot.open_reader(str(path))
            if not any(e.move == chess.Move.from_uci(reply) for e in r.find_all(b)):
                missing.append(f"{first} {reply}")
            r.close()
    if missing:
        print(f"(c) FAIL: missing required lines: {missing}")
        ok = False
    else:
        print("(c) coverage: 1.e4/1.d4/1.Nf3/1.c4 present; replies "
              "e5/c5/e6/c6/d5/Nf6 present after 1.e4 and 1.d4")
    print("VALIDATION", "OK" if ok else "FAILED")
    return 0 if ok else 1


# --------------------------------------------------------------------------
#  main
# --------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--month", help="Lichess month, e.g. 2016-01 (downloads it)")
    ap.add_argument("--pgn", type=Path, help="local .pgn or .pgn.zst (no download)")
    ap.add_argument("--url", help="override the source URL")
    ap.add_argument("--sha256", help="expected SHA256 of the compressed source")
    ap.add_argument("--cache", type=Path, default=Path("/tmp/opencode"),
                    help="download cache directory (default /tmp/opencode)")
    ap.add_argument("--out", type=Path, default=ROOT / "books" / "babachess-book.bin")
    # The defaults are calibrated against the stated size target (tens of
    # thousands of entries) WITHOUT breaking the minimal-coverage test:
    # e2e4 g8f6 is only the 7th most played reply after 1.e4 (needs
    # --max-moves 10), and d2d4 e7e5 (1.0%), d2d4 c7c6 (2.4%) and the
    # 0.4497-scoring d2d4 e7e6 (1.0%) all fall out of the stricter defaults.
    # See books/README.md for the measured trade-off.
    ap.add_argument("--min-elo", type=int, default=2000,
                    help="both players must be at least this rated (default "
                         "2000: a Lichess month has only ~29k games at 2200)")
    ap.add_argument("--max-games", type=int, default=0,
                    help="stop after N games scanned (0 = all; bounds time)")
    ap.add_argument("--max-ply", type=int, default=MAX_PLY,
                    help=f"max plies kept per game (engine limit {MAX_PLY})")
    ap.add_argument("--min-pos", type=int, default=5,
                    help="a position must be seen at least N times")
    ap.add_argument("--min-move", type=int, default=4,
                    help="a move must be played at least N times")
    ap.add_argument("--min-move-share", type=float, default=1.0,
                    help="a move must be >= this %% of the position's games")
    ap.add_argument("--min-score", type=float, default=0.44,
                    help="mover's expected score must be >= this (0..1)")
    ap.add_argument("--max-moves", type=int, default=10,
                    help="at most this many moves kept per position")
    ap.add_argument("--cache-stats", action="store_true",
                    help="cache/load the per-(position,move) stats as JSON so "
                         "threshold tuning does not re-parse the source")
    ap.add_argument("--stats-cache", type=Path,
                    help="stats cache file (implies --cache-stats)")
    ap.add_argument("--stockfish", help="optional Stockfish binary to prune moves")
    ap.add_argument("--depth", type=int, default=12, help="Stockfish depth")
    ap.add_argument("--drop-cp", type=int, default=60,
                    help="drop moves worse than best by more than this (cp)")
    ap.add_argument("--bad-cp", type=int, default=50,
                    help="drop moves below -this cp absolute (mover POV)")
    ap.add_argument("--validate", type=Path, metavar="BOOK",
                    help="validate an existing book and exit")
    args = ap.parse_args()

    if args.validate:
        return validate(args.validate)
    if not args.month and not args.pgn:
        ap.error("give --month or --pgn (or --validate)")

    # --- source -----------------------------------------------------------
    src_path = args.pgn
    url = args.url or (month_url(args.month) if args.month else None)
    sha = None
    if src_path is None:
        cache = args.cache / Path(url).name
        if cache.exists() and cache.stat().st_size > 0:
            print(f"using cached {cache}", file=sys.stderr)
        else:
            download(url, cache, args.sha256)
        src_path = cache
    # SHA256 of whatever local compressed source we used.
    h = hashlib.sha256()
    with open(src_path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    sha = h.hexdigest()

    stats = Stats()
    use_cache = args.cache_stats or args.stats_cache is not None
    cache = args.stats_cache or (
        args.cache / f"bookstats-{args.min_elo}-{args.max_ply}-{args.max_games}.json")
    if use_cache and cache.exists():
        print(f"using cached stats {cache}", file=sys.stderr)
        stats.moves, counters = load_stats_cache(cache)
    else:
        stream = open_pgn(src_path)
        counters = collect_games(args, stream, stats)
        try:
            stream.close()
        except Exception:  # noqa: BLE001
            pass
        if use_cache:
            save_stats_cache(cache, stats, counters)

    # --- select -----------------------------------------------------------
    entries = select_entries(stats, args)
    write_book(args.out, entries)

    print(f"source   : {url or src_path}")
    print(f"sha256   : {sha}")
    print(f"games    : scanned {counters['seen']}, "
          f"qualifying (Elo >= {args.min_elo}) {counters['qualifying']}, "
          f"plies kept {counters['plies']}")
    print(f"positions: {len(stats.moves)} with >=1 game")
    print(f"book     : {len(entries)} entries = {args.out.stat().st_size} bytes "
          f"({args.out.stat().st_size/1024/1024:.2f} MiB)")

    # --- optional Stockfish pruning --------------------------------------
    if args.stockfish:
        build_pos_index(entries)
        res = stockfish_prune(args.out, args.stockfish, args.depth,
                              args.drop_cp, args.bad_cp)
        print(f"stockfish: kept {res['kept']}, removed {res['removed']} "
              f"(depth {args.depth})")
    else:
        print("stockfish: step NOT run (no --stockfish given)")

    # --- self-validate ----------------------------------------------------
    return validate(args.out)


if __name__ == "__main__":
    sys.exit(main())
