#!/usr/bin/env bash
# SPRT between the default evaluation and the same binary driven by a
# --params file.  No rebuild is needed: NEW is a tiny wrapper that execs the
# binary with `--params <file>` (the pattern scripts/spsa.py uses for SPSA).
#
# This is how a *tunable* evaluation change (e.g. enabling the drawish-endgame
# scale factor) is validated without baking it into the source first:
#
#   scripts/sprt_params.sh 1+0.1 0 5 2000 7 /tmp/opencode/scale.params bin/babachess
#
# Usage:
#   scripts/sprt_params.sh [tc] [elo0] [elo1] [max_games] [seed] [params_file] [binary]
#
#   params_file  P_* / S_* overrides applied to NEW (required)
#   binary       engine binary for BOTH sides (default bin/babachess)
#
# Everything else (ALPHA, BETA, OPENINGS, NODES, PROTO) is forwarded to
# scripts/sprt.sh.  Requires cutechess-cli on PATH.
set -euo pipefail

TC="${1:-1+0.1}"
ELO0="${2:-0}"
ELO1="${3:-5}"
MAXGAMES="${4:-2000}"
SEED="${5:-7}"
PARAMS="${6:-}"
BASE="${7:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${BASE:-${ROOT}/bin/babachess}"

if [ -z "$PARAMS" ]; then
  echo "usage: sprt_params.sh [tc] [elo0] [elo1] [max_games] [seed] params_file [binary]" >&2
  exit 2
fi
[ -f "$PARAMS" ] || { echo "params file not found: $PARAMS" >&2; exit 2; }
[ -x "$BASE" ] || { echo "engine not executable: $BASE" >&2; exit 2; }
command -v cutechess-cli >/dev/null || { echo "cutechess-cli not found on PATH" >&2; exit 2; }

PARAMS="$(realpath "$PARAMS")"
BASE="$(realpath "$BASE")"

mkdir -p /tmp/opencode
WRAP="/tmp/opencode/sprt_params_wrap_$$.sh"
cleanup() { rm -f "$WRAP"; }
trap cleanup EXIT

cat > "$WRAP" <<EOF
#!/bin/sh
exec "\$BABACHESS_BASE" --params "\$BABACHESS_PARAMS" "\$@"
EOF
chmod 755 "$WRAP"

echo "params SPRT: OLD = $BASE            (default eval)"
echo "             NEW = wrapper -> $BASE --params $PARAMS"
echo "             params: $(tr '\n' ' ' < "$PARAMS")"

# sprt.sh applies --params/--threads to every mode, so the override is honoured
# on both the UCI and XBoard paths.
#
# The wrapper must stay *lazy*: sprt.sh runs `realpath "$NEW"`, which fails on
# a dangling symlink -- so we cannot export WRAP as a symlink to the engine
# (it would be resolved away before the match starts).  Instead the wrapper
# exec's the engine through env vars set here; `exec` keeps it a single
# process so cutechess-cli talks directly to the engine over its pipes.
export BABACHESS_BASE="$BASE"
export BABACHESS_PARAMS="$PARAMS"
"$ROOT/scripts/sprt.sh" "$TC" "$ELO0" "$ELO1" "$MAXGAMES" "$SEED" "$BASE" "$WRAP"
