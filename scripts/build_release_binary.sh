#!/usr/bin/env bash
#
# Build a release-distribution binary with NO GNAT runtime dependency.
#
# A plain gprbuild link against a shared GNAT produces a binary that needs
# libgnat-<ver>.so / libgnarl-<ver>.so at run time. This script links those
# statically: it makes versioned symlinks named exactly as GNAT asks
# (libgnat-<major>.a) pointing at the shipped static archives, and passes
# -static. The result is `ldd`-clean apart from the libc/ld-linux pair, so an
# end user does not need GNAT installed.
#
# Usage: scripts/build_release_binary.sh [release|portable]
#
# Linux only (on Windows the GNAT runtime is linked statically by default).
set -euo pipefail

MODE="${1:-release}"
case "$MODE" in release|portable) ;; *) echo "mode: release or portable" >&2; exit 2 ;; esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MAJOR="$(gcc -dumpversion | cut -d. -f1)"
ADALIB="$(gnatls -v 2>/dev/null | sed -n 's#.*: *\(/.*adalib\)$#\1#p' | head -1)"
if [ -z "$ADALIB" ] || [ ! -f "$ADALIB/libgnat.a" ]; then
  CAND="$(dirname "$(gcc -print-file-name=libgnat.a 2>/dev/null)")"
  [ -f "$CAND/libgnat.a" ] && ADALIB="$CAND"
fi
if [ -z "$ADALIB" ] || [ ! -f "$ADALIB/libgnat.a" ]; then
  ADALIB="$(find /usr/lib/gcc -type d -name adalib -print -quit 2>/dev/null || true)"
fi
[ -n "$ADALIB" ] && [ -f "$ADALIB/libgnat.a" ] \
  || { echo "cannot locate adalib/libgnat.a (is GNAT installed?)" >&2; exit 1; }

mkdir -p build/static-libs
ln -sf "$ADALIB/libgnat.a"  "build/static-libs/libgnat-$MAJOR.a"
ln -sf "$ADALIB/libgnarl.a" "build/static-libs/libgnarl-$MAJOR.a"

rm -rf obj
gprbuild -P babachess.gpr -XMode="$MODE" \
  -largs -static -L"$ROOT/build/static-libs"

echo "built bin/babachess ($MODE, statically linked GNAT runtime)"
