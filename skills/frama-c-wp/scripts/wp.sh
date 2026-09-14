#!/usr/bin/env bash
# Canonical Frama-C/WP run: environment preamble + verified flag set + soundness scan.
#
# Usage:  wp.sh [options] <file.c> [more.c ...]
#
#   -s DIR      session directory   (default: ./.wp-session)
#   -t SECS     prover timeout      (default: 2)
#   -j N        parallel provers    (default: all cores)
#   -f FN       restrict to function FN
#   -p PROP     restrict to clause named PROP
#   -m MODEL    memory model        (default: Typed)
#   -P LIST     provers, comma-sep  (default: alt-ergo,cvc5,z3)
#   -C MODE     cache mode          (default: update)
#   -I DIR      add an include dir for annotations (repeatable)
#   -S          also run smoke tests in this pass (one invocation instead of two)
#   -R          disable -wp-rte     (only to isolate a functional goal; never to finish)
#   -U          keep -wp-rte but drop -warn-unsigned-overflow / -warn-unsigned-downcast,
#               for a codebase whose idioms make them false by construction (kernel byte and
#               counter idioms -- see verifiable-c/references/hostile-c.md). Frama-C says
#               nothing when they are off, so the verdict marks the run REDUCED instead.
#   -x ARGS     extra raw frama-c arguments
#
# Exit: 0 all goals proved and no soundness findings; 1 unproved goals; 2 WP aborted;
#       3 goals proved but soundness findings present -- result is NOT evidence.

set -uo pipefail

SESSION=./.wp-session; TIMEOUT=2; PAR=$(nproc 2>/dev/null || echo 4); FCT=""; PROP=""; MODEL="Typed"
PROVERS="alt-ergo,cvc5,z3"; CACHE="update"; RTE=1; UNSIGNED=1; SMOKE=0; EXTRA=""; INCS=()

while getopts "s:t:j:f:p:m:P:C:I:RUSx:h" o; do
  case "$o" in
    s) SESSION="$OPTARG" ;; t) TIMEOUT="$OPTARG" ;; j) PAR="$OPTARG" ;;
    f) FCT="$OPTARG"   ;; p) PROP="$OPTARG"   ;; m) MODEL="$OPTARG" ;;
    P) PROVERS="$OPTARG" ;; C) CACHE="$OPTARG" ;; R) RTE=0 ;; U) UNSIGNED=0 ;;
    S) SMOKE=1 ;; x) EXTRA="$OPTARG" ;;
    I) INCS+=("-I$OPTARG") ;;
    h) sed -n '2,/^$/p' "$0"; exit 0 ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
[ $# -ge 1 ] || { echo "wp.sh: no input file" >&2; exit 2; }

. "$(dirname "$0")/env.sh"

mkdir -p "$SESSION"
REPORT="$SESSION/report.json"
LOG="$SESSION/run.log"

FLAGS=(-pp-annot -no-unicode -wp -wp-model "$MODEL" -wp-split
       -wp-timeout "$TIMEOUT" -wp-par "$PAR" -wp-cache "$CACHE"
       -wp-session "$SESSION" -wp-interactive=batch -wp-report-json "$REPORT")
export WP_UNSIGNED="$UNSIGNED"
# shellcheck disable=SC2207
[ "$RTE" = 1 ] && FLAGS+=($(wp_rte_flags))
[ "$SMOKE" = 1 ] && FLAGS+=(-wp-smoke-tests -wp-smoke-timeout "$TIMEOUT")
for p in ${PROVERS//,/ }; do FLAGS+=(-wp-prover "$p"); done
[ ${#INCS[@]} -gt 0 ] && FLAGS+=("-cpp-extra-args=${INCS[*]}")
[ -n "$FCT" ]  && FLAGS+=(-wp-fct "$FCT")
[ -n "$PROP" ] && FLAGS+=(-wp-prop="$PROP")
# shellcheck disable=SC2206
[ -n "$EXTRA" ] && FLAGS+=($EXTRA)

frama-c "${FLAGS[@]}" "$@" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}

echo
echo "--- wp.sh verdict ---------------------------------------------"

# Tier A: WP refused to analyse. No goal count from this run is meaningful.
if grep -qE 'User Error|Non-natural loop detected|is \(potentially\) recursive' "$LOG"; then
  grep -hE -A1 'User Error' "$LOG" | grep -vE '^\[wp\].*User Error: *$|^--$' \
    | sed 's/^ *//' | sort -u | sed 's/^/  ABORT  /'
  echo "  => WP aborted. Restructure the C; see frama-c-wp/references/limitations.md tier A."
  exit 2
fi

# Tier B: findings that make a "proved" result untrustworthy.
B='might be unsound|Missing RTE guards|not yet supported \(skipped\)|interpreted as reads nothing|using unguarded behavior assigns|using complete behaviors assigns|Memory model hypotheses for function|Failed smoke-test'
UNSOUND=0
if grep -qE "$B" "$LOG"; then
  grep -hoE "$B" "$LOG" | sort | uniq -c | sed 's/^/  UNSOUND/'
  UNSOUND=1
fi

# Always-emitted assumptions. Harmless unless the code actually relies on them:
# WP never generates RTE guards for pointer alignment or function-pointer validity.
if grep -q 'Skipped RTE guards' "$LOG"; then
  grep -hoE 'Skipped RTE guards: [^)]*\)' "$LOG" | sort -u | sed 's/^/  ASSUME /'
  # An indirect call with these guards skipped is a real hole, not a formality.
  # Match only real indirect-call diagnostics -- NOT the always-emitted
  # "Skipped RTE guards: ... (\valid_function not supported)" line above.
  if grep -qE "Missing .calls.|Unknown callee" "$LOG"; then
    echo "  UNSOUND  indirect call present while \\valid_function guards are skipped"
    UNSOUND=1
  fi
fi

# Dropping the two unsigned checks produces no Frama-C diagnostic at all -- verified, so
# the reduction is invisible unless we say it. Printed here rather than on the success path
# only: it is just as true of a run that exits 1 or 3.
if [ "$RTE" = 1 ] && wp_rte_reduced; then
  echo "  REDUCED  -warn-unsigned-overflow / -warn-unsigned-downcast were OFF"
  echo "           unsigned wraparound and narrowing are NOT checked in this run"
  echo "           name the idiom that forced it when you report this result"
fi

PROVED=$(grep -oE 'Proved goals: +[0-9]+ */ *[0-9]+' "$LOG" | tail -1)
echo "  ${PROVED:-Proved goals: (none reported)}"
echo "  report: $REPORT"

if [ "$rc" -ne 0 ]; then echo "  => frama-c exit $rc"; exit 2; fi
if ! echo "$PROVED" | grep -qE '([0-9]+) */ *\1$'; then
  echo "  => unproved goals remain; see frama-c-wp/references/triage.md"; exit 1
fi
if [ "$UNSOUND" = 1 ]; then
  echo "  => all goals proved BUT soundness findings above: this is NOT evidence."
  echo "     Fix them, then re-run. See frama-c-wp/references/limitations.md tier B."; exit 3
fi
if [ "$SMOKE" = 1 ]; then
  echo "  => all goals proved, no soundness findings, smoke tests clean."
else
  echo "  => all goals proved, no soundness findings. Now run wp-smoke.sh."
fi
exit 0
