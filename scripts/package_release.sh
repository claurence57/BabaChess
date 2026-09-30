#!/usr/bin/env bash
#
# Assemble one release archive for BabaChess.
#
# The archive contains the engine binary, the licences (project GPL, NOTICE,
# the Fathom MIT licence), README, the release notes, and the bundled book at
# books/book.bin (the location the engine probes by default).
#
# Archive format: .tar.gz on Linux, .zip on Windows. Both are produced by an
# embedded Python 3 snippet so the script behaves identically under git-bash
# on Windows and on Linux (no dependency on zip/tar quirks).
#
# Usage:
#   scripts/package_release.sh --binary PATH --os linux|windows \
#       --build bmi2|portable --version 1.0.0 --book PATH [--outdir DIR]
#
# Writes the archive and a sibling <archive>.sha256 sidecar (portable, no
# line-ending ambiguity when the artifacts are concatenated in CI).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTDIR="$ROOT/dist"
VERSION=""
OS=""
BUILD=""
BINARY=""
BOOK=""

while [ $# -gt 0 ]; do
  case "$1" in
    --binary) BINARY="$2"; shift 2 ;;
    --os) OS="$2"; shift 2 ;;
    --build) BUILD="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --book) BOOK="$2"; shift 2 ;;
    --outdir) OUTDIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

[ -n "$BINARY" ] && [ -n "$OS" ] && [ -n "$BUILD" ] && [ -n "$VERSION" ] \
  || { echo "missing required option (see --help)" >&2; exit 2; }
[ -x "$BINARY" ] || { echo "binary not executable: $BINARY" >&2; exit 2; }
[ -f "$BOOK" ] || { echo "book not found: $BOOK" >&2; exit 2; }
case "$OS" in linux|windows) ;; *) echo "bad --os: $OS" >&2; exit 2 ;; esac
case "$BUILD" in bmi2|portable) ;; *) echo "bad --build: $BUILD" >&2; exit 2 ;; esac

NAME="babachess-${VERSION}-${OS}-x86_64-${BUILD}"
STAGE="$OUTDIR/$NAME"
[ "$OS" = windows ] && EXE="babachess.exe" || EXE="babachess"

rm -rf "$STAGE"
mkdir -p "$STAGE/books" "$STAGE/src/fathom"

cp "$BINARY" "$STAGE/$EXE"
cp "$BOOK" "$STAGE/books/book.bin"
cp "$ROOT/LICENSE" "$STAGE/LICENSE"
cp "$ROOT/NOTICE.md" "$STAGE/NOTICE.md"
cp "$ROOT/README.md" "$STAGE/README.md"
cp "$ROOT/RELEASE_NOTES_${VERSION}.md" "$STAGE/RELEASE_NOTES_${VERSION}.md"
cp "$ROOT/src/fathom/LICENSE" "$STAGE/src/fathom/LICENSE"
[ "$OS" = windows ] || chmod +x "$STAGE/$EXE"

EXT="tar.gz"; [ "$OS" = windows ] && EXT="zip"

python3 - "$OUTDIR" "$NAME" "$EXT" <<'PY'
import os, sys, tarfile, zipfile
outdir, name, ext = sys.argv[1], sys.argv[2], sys.argv[3]
stage = os.path.join(outdir, name)
arc = os.path.join(outdir, f"{name}.{ext}")
if ext == "zip":
    with zipfile.ZipFile(arc, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _dirs, files in os.walk(stage):
            for f in files:
                p = os.path.join(root, f)
                z.write(p, os.path.relpath(p, outdir))
else:
    with tarfile.open(arc, "w:gz") as t:
        t.add(stage, arcname=name)
print(arc)
PY

HASH="$(sha256sum "$OUTDIR/${NAME}.${EXT}" | cut -d' ' -f1)"
printf '%s  %s\n' "$HASH" "${NAME}.${EXT}" > "$OUTDIR/${NAME}.${EXT}.sha256"
echo "archive: $OUTDIR/${NAME}.${EXT}"
echo "$HASH  ${NAME}.${EXT}"
