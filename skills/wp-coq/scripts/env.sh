#!/usr/bin/env bash
# Resolve the Frama-C toolchain. Sourced by the other scripts in this directory; not run
# directly. Kept byte-identical between frama-c-wp/scripts/ and wp-coq/scripts/ so each
# skill's scripts work with that skill alone installed.
#
# Resolution order:
#   1. $FRAMAC_SWITCH        — explicit opam switch name, if you set it
#   2. the opam switch that actually contains frama-c
#   3. frama-c already on PATH — no opam involved (system install, nix, container)
#
# Also prepends $FRAMAC_EXTRA_BIN (default ~/.local/bin) so a solver installed outside
# opam — cvc5 is the usual one — is visible to Why3.

_fc_env() {
  local sw
  if [ -n "${FRAMAC_SWITCH-}" ]; then
    sw="$FRAMAC_SWITCH"
  elif command -v opam >/dev/null 2>&1; then
    # Pick the switch that has frama-c installed; prefer the current one if it qualifies.
    local cur; cur=$(opam switch show 2>/dev/null)
    if [ -n "$cur" ] && [ -x "$(opam var --switch="$cur" bin 2>/dev/null)/frama-c" ]; then
      sw="$cur"
    else
      local s
      for s in $(opam switch list --short 2>/dev/null); do
        if [ -x "$(opam var --switch="$s" bin 2>/dev/null)/frama-c" ]; then sw="$s"; break; fi
      done
    fi
  fi

  if [ -n "${sw-}" ]; then
    eval "$(opam env --switch="$sw" --set-switch 2>/dev/null)"
  fi

  export PATH="${FRAMAC_EXTRA_BIN:-$HOME/.local/bin}:$PATH"

  if ! command -v frama-c >/dev/null 2>&1; then
    echo "no frama-c found." >&2
    echo "  Set FRAMAC_SWITCH=<opam switch>, or put frama-c on PATH." >&2
    return 1
  fi
}

_fc_env || exit 2

# RTE policy, in one place because all three wrappers need it. The two unsigned checks are
# on by default; WP_UNSIGNED=0 drops them for a codebase whose idioms make them false by
# construction (see verifiable-c/references/hostile-c.md). Frama-C says nothing when they
# are off, so a caller that honours this must announce the reduction itself.
wp_rte_flags() {
  printf '%s' "-wp-rte"
  [ "${WP_UNSIGNED:-1}" = 1 ] && printf ' %s' "-warn-unsigned-overflow" "-warn-unsigned-downcast"
  printf '\n'
}
wp_rte_reduced() { [ "${WP_UNSIGNED:-1}" != 1 ]; }
