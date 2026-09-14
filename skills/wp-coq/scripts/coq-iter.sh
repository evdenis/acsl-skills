#!/usr/bin/env bash
# Fast Coq iteration on a WP proof obligation, without going through Frama-C each time.
# Typechecks <session>/interactive/<goal>.v directly -- roughly 1s instead of 15s.
#
# Usage:  coq-iter.sh <path/to/goal.v>
#
# Insert `Show.` anywhere in the proof to print the goal state at that point, then re-run.
# When it reports "proof OK", confirm through WP with:
#   frama-c ... -wp-prover coq -wp-interactive batch -wp-session <session> file.c
#
# Only edit between `Proof.` and `Qed.` -- the generated preamble above is rewritten by
# `-wp-interactive update` and any edit there is destroyed.

set -uo pipefail
usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }
case "${1-}" in -h|--help|"") usage; exit 0 ;; esac
[ $# -eq 1 ] || { usage; exit 2; }
V="$1"
[ -f "$V" ] || { echo "coq-iter.sh: no such file: $V" >&2; exit 2; }

. "$(dirname "$0")/env.sh"

W="$(why3 --print-libdir)"
out=$(coqtop -batch -R "$W/coq" Why3 -l "$V" 2>&1)
rc=$?
echo "$out"
if [ $rc -eq 0 ] && ! echo "$out" | grep -q '^Error'; then
  echo "--- proof OK. Confirm with: -wp-prover coq -wp-interactive batch"
  exit 0
fi
echo "--- proof failed."
echo "$out" | grep -E '^(File|Error)' | head -5 | sed 's/^/    /'
cat <<'MSG'
    Common causes:
      "Cannot find witness."        lia lacks a hypothesis -- add `Show.` before it
      "not found in the current .." wrong lemma name; check the Q_/L_/P_ mangling
      "Unable to unify"             a `replace` pattern did not match; Coq prints -1 as
                                    `- (1)`, so `replace (-1)%Z` silently fails to match
MSG
exit 1
