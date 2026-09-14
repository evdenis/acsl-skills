#!/usr/bin/env bash
# Drill into one failing goal: re-run just that clause and dump the raw verification
# condition. Requires named clauses (`requires valid:`, `loop invariant bound:`).
#
# Usage:  wp-goal.sh -f FUNCTION [-p CLAUSE] [-s DIR] [-t SECS] [-I DIR]... [-r] <file.c> ...
#
#   -f FN     function to isolate            (required)
#   -p NAME   clause name to isolate         (recommended; else all goals of FN)
#   -t SECS   timeout                        (default: 20 -- higher than a batch run)
#   -r        raw VC: adds -wp-print -wp-no-qed so you see it unsimplified
#   -P LIST   provers                        (default: alt-ergo,cvc5,z3)
#   -j N      parallel provers                (default: all cores)
#   -C MODE   cache mode                      (default: none -- measured faster here: a single
#             function's goals are usually sub-second, so WP's content-hash lookup costs more
#             than re-proving. Use update if your goals take seconds.)
#
# Read the output as: "Assume" = what WP believes at that point, "Prove" = the obligation.
# If a fact you expected is missing from Assume, the invariant or precondition that should
# have supplied it is too weak. That is the fix -- not a longer timeout.

set -uo pipefail
SESSION=./.wp-session; TIMEOUT=20; FCT=""; PROP=""; RAW=0; PROVERS="alt-ergo,cvc5,z3"
PAR=$(nproc 2>/dev/null || echo 4); CACHE="none"; INCS=()
while getopts "f:p:s:t:I:P:j:C:rh" o; do
  case "$o" in f) FCT="$OPTARG";; p) PROP="$OPTARG";; s) SESSION="$OPTARG";;
               t) TIMEOUT="$OPTARG";; I) INCS+=("-I$OPTARG");; P) PROVERS="$OPTARG";;
               j) PAR="$OPTARG";; C) CACHE="$OPTARG";;
               r) RAW=1;; h) sed -n '2,15p' "$0"; exit 0;; *) exit 2;; esac
done
shift $((OPTIND - 1))
[ -n "$FCT" ] || { echo "wp-goal.sh: -f FUNCTION is required" >&2; exit 2; }
[ $# -ge 1 ]  || { echo "wp-goal.sh: no input file" >&2; exit 2; }

. "$(dirname "$0")/env.sh"
mkdir -p "$SESSION"

# shellcheck disable=SC2207
FLAGS=(-pp-annot -no-unicode -wp $(wp_rte_flags)
       -wp-model Typed -wp-session "$SESSION" -wp-cache "$CACHE"
       -wp-timeout "$TIMEOUT" -wp-par "$PAR" -wp-fct "$FCT")
[ -n "$PROP" ] && FLAGS+=(-wp-prop="$PROP")
[ "$RAW" = 1 ] && FLAGS+=(-wp-print -wp-no-qed)
for p in ${PROVERS//,/ }; do FLAGS+=(-wp-prover "$p"); done
[ ${#INCS[@]} -gt 0 ] && FLAGS+=("-cpp-extra-args=${INCS[*]}")

exec frama-c "${FLAGS[@]}" "$@"
