#!/usr/bin/env bash
# Vacuity gate. A contradictory `requires`, a dead branch or an unreachable loop makes every
# goal in scope provable. Nothing is verified until this passes.
#
# Usage:  wp-smoke.sh [-s DIR] [-t SECS] [-j N] [-I DIR]... [-x ARGS] <file.c> ...
# Exit:   0 clean; 1 smoke tests failed (vacuous spec or dead code); 2 WP error.

set -uo pipefail
SESSION=./.wp-session; TIMEOUT=5; PAR=$(nproc 2>/dev/null || echo 4); EXTRA=""; INCS=()
while getopts "s:t:j:I:x:h" o; do
  case "$o" in s) SESSION="$OPTARG";; t) TIMEOUT="$OPTARG";; j) PAR="$OPTARG";; I) INCS+=("-I$OPTARG");;
               x) EXTRA="$OPTARG";; h) sed -n '2,6p' "$0"; exit 0;; *) exit 2;; esac
done
shift $((OPTIND - 1))
[ $# -ge 1 ] || { echo "wp-smoke.sh: no input file" >&2; exit 2; }

. "$(dirname "$0")/env.sh"
mkdir -p "$SESSION"; LOG="$SESSION/smoke.log"

# shellcheck disable=SC2207
FLAGS=(-pp-annot -no-unicode -wp $(wp_rte_flags)
       -wp-model Typed -wp-session "$SESSION" -wp-timeout "$TIMEOUT" -wp-par "$PAR"
       -wp-smoke-tests -wp-smoke-timeout "$TIMEOUT"
       -wp-prover alt-ergo -wp-prover cvc5 -wp-prover z3)
[ ${#INCS[@]} -gt 0 ] && FLAGS+=("-cpp-extra-args=${INCS[*]}")
# shellcheck disable=SC2206
[ -n "$EXTRA" ] && FLAGS+=($EXTRA)

frama-c "${FLAGS[@]}" "$@" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}

echo
echo "--- wp-smoke.sh verdict ---------------------------------------"
if grep -qE 'User Error' "$LOG"; then echo "  => WP error, smoke result meaningless"; exit 2; fi
if grep -qE 'Failed smoke-test|Unsuccess.*smoke' "$LOG"; then
  grep -hE 'Failed smoke-test|Unsuccess.*smoke' "$LOG" | sed 's/^/  VACUOUS /' | sort -u
  cat <<'MSG'
  => A smoke test failed. Something in scope is unreachable or contradictory, so the
     goals around it prove for the wrong reason. Find which:
       dead code    -> an `if` branch or statement WP proved unreachable
       dead assumes -> a `requires` or `assumes` no caller state can satisfy
       dead loop    -> a loop body that never runs
       dead call    -> a call site WP proved unreachable
     Fix the specification, not the smoke test.
MSG
  exit 1
fi
echo "  => no vacuity detected"
exit "$rc"
