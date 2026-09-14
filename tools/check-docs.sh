#!/usr/bin/env bash
# Consistency check for this skillset. Run after editing anything under skills/, and after
# any Frama-C or prover upgrade.
#
# Usage:  tools/check-docs.sh [-q]     -q skips the slow checks (prover probe, template typecheck)
#
# It exists because the same fact is deliberately stated in more than one place: a SKILL.md
# body is always loaded once its skill fires, so the common path is restated there rather
# than hidden behind a pointer. That design is only safe if the copies are checked.

set -uo pipefail
QUICK=0; [ "${1-}" = "-q" ] && QUICK=1
ROOT=$(cd "$(dirname "$0")/.." && pwd) || exit 2
cd "$ROOT" || exit 2
fail=0
note() { printf "  %-6s %s\n" "$1" "$2"; [ "$1" = FAIL ] && fail=1; return 0; }

SKILLS="acsl-verify acsl-spec frama-c-wp verifiable-c wp-coq"
SK_RE=$(echo "$SKILLS" | tr ' ' '|')
FILES=$(find skills -type f | sort)

# ---------------------------------------------------------------- frontmatter
echo "--- frontmatter (agentskills.io spec)"
# The intersection of the Agent Skills spec and Codex: the spec also defines
# `compatibility`, but Codex rejects it, so requirements live in the body instead.
SPEC_KEYS="name description license metadata allowed-tools"
for d in $SKILLS; do
  f="skills/$d/SKILL.md"
  [ -f "$f" ] || { note FAIL "$f missing"; continue; }
  [ "$(head -1 "$f")" = "---" ] || { note FAIL "$f: no opening ---"; continue; }
  end=$(awk 'NR>1 && $0=="---" {print NR; exit}' "$f")
  [ -n "$end" ] || { note FAIL "$f: frontmatter never closed"; continue; }
  fm=$(sed -n "2,$((end-1))p" "$f")

  # only spec-defined top-level keys
  while read -r k; do
    [ -n "$k" ] || continue
    case " $SPEC_KEYS " in *" $k "*) ;; *) note FAIL "$f: non-spec frontmatter key '$k'";; esac
  done <<< "$(printf '%s\n' "$fm" | sed -n 's/^\([a-z][a-z-]*\):.*/\1/p')"

  n=$(printf '%s\n' "$fm" | sed -n 's/^name: *//p')
  [ "$n" = "$d" ] || note FAIL "$f: name '$n' != directory '$d'"
  [ "${#n}" -le 64 ] || note FAIL "$f: name longer than 64 chars"
  printf '%s' "$n" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$' \
    || note FAIL "$f: name '$n' is not lowercase-alphanumeric-hyphen"

  desc=$(printf '%s\n' "$fm" | sed -n 's/^description: *//p')
  [ -n "$desc" ] || note FAIL "$f: empty description"
  [ "${#desc}" -le 1024 ] || note FAIL "$f: description ${#desc} chars, max 1024"

  # Codex rejects angle brackets in a description; the spec does not.
  case "$desc" in *"<"*|*">"*) note FAIL "$f: description contains angle brackets, which Codex rejects";; esac

  printf '%s\n' "$fm" | grep -q '^license: MIT$' || note FAIL "$f: missing 'license: MIT'"

  lines=$(wc -l < "$f")
  [ "$lines" -lt 500 ] || note FAIL "$f: $lines lines, spec says keep under 500"
  [ "$lines" -lt 300 ] || note warn "$f: $lines lines - consider moving detail to references/"
done
note ok "5 skills well-formed"

# ---------------------------------------------------------------- references
echo "--- references resolve"
for f in $FILES; do
  d=${f#skills/}; d=${d%%/*}
  # intra-skill:  references/x.md  scripts/x.sh  assets/x
  for m in $(grep -ohE '(^|[^/A-Za-z0-9_-])(references|scripts|assets)/[A-Za-z0-9_.-]+' "$f" \
             | sed -E 's/^[^A-Za-z]*//' | sort -u); do
    [ -e "skills/$d/$m" ] || note FAIL "$f -> $m (not in skills/$d/)"
  done
  # cross-skill:  <skill>/references/x.md
  for m in $(grep -ohE "($SK_RE)/(references|scripts|assets)/[A-Za-z0-9_.-]+" "$f" | sort -u); do
    [ -e "skills/$m" ] || note FAIL "$f -> $m (no such file)"
  done
  # ${CLAUDE_SKILL_DIR}/[../<skill>/]{scripts,assets}/x
  for m in $(grep -ohE '\$\{CLAUDE_SKILL_DIR\}/(\.\./[a-z0-9-]+/)?(references|scripts|assets)/[A-Za-z0-9_.-]+' "$f" \
             | sed 's|${CLAUDE_SKILL_DIR}/||' | sort -u); do
    case "$m" in
      ../*) [ -e "skills/${m#../}" ] || note FAIL "$f -> CLAUDE_SKILL_DIR/$m (no such file)" ;;
      *)    [ -e "skills/$d/$m" ]    || note FAIL "$f -> CLAUDE_SKILL_DIR/$m (not in skills/$d/)" ;;
    esac
  done
  # by-name skill mentions
  for m in $(grep -ohE "\`($SK_RE)\`" "$f" | tr -d '`' | sort -u); do
    [ -f "skills/$m/SKILL.md" ] || note FAIL "$f names skill '$m', which does not exist"
  done
  # bare x.md names are retired: every .md mention must be anchored
  bare=$(grep -ohE '(^|[^/A-Za-z0-9_-])[a-z][a-z0-9-]*\.md\b' "$f" \
         | sed -E 's/^[^A-Za-z]*//' | grep -vE '^(SKILL|README)\.md$' | sort -u)
  [ -z "$bare" ] || note FAIL "$f: unanchored .md reference(s): $(echo $bare | tr '\n' ' ')"
done
note ok "all resolve"

echo "--- no orphan bundled files"
for p in $(find skills -type f \( -path '*/references/*' -o -path '*/scripts/*' -o -path '*/assets/*' \) | sort); do
  b=$(basename "$p")
  grep -qr -- "$b" skills --exclude="$b" || note FAIL "orphan: $p is referenced by nothing"
done
note ok "none"

echo "--- documented scripts exist and are executable"
for m in $(grep -rohE "(($SK_RE)/)?scripts/[a-z-]+\.sh" skills | sort -u); do
  case "$m" in
    scripts/*) for d in $SKILLS; do [ -e "skills/$d/$m" ] && { [ -x "skills/$d/$m" ] || note FAIL "not executable: skills/$d/$m"; }; done ;;
    *)         [ -x "skills/$m" ] || note FAIL "missing or not executable: skills/$m" ;;
  esac
done
note ok "all executable"

# ---------------------------------------------------------------- layout hygiene
echo "--- script paths stay portable between harnesses"
# Codex does not expand ${CLAUDE_SKILL_DIR}; commands must use skill-relative paths and
# each skill says once, in prose, that they need prefixing.
for f in skills/*/SKILL.md skills/*/references/*.md; do
  awk -v F="$f" '
    /^```/ { inc = !inc; next }
    inc && /\$\{CLAUDE_SKILL_DIR\}/ { print "  FAIL   " F ":" NR ": ${CLAUDE_SKILL_DIR} inside a command block (Codex cannot expand it)"; bad=1 }
    END { exit bad?1:0 }' "$f" || fail=1
done
for d in frama-c-wp wp-coq acsl-verify acsl-spec; do
  grep -qE 'scripts/[a-z-]+\.sh' "skills/$d/SKILL.md" || continue
  grep -q 'CLAUDE_SKILL_DIR' "skills/$d/SKILL.md" \
    || note FAIL "skills/$d/SKILL.md runs a script but never says paths are skill-relative"
done
note ok "commands are skill-relative"

echo "--- Codex presentation config"
for d in $SKILLS; do
  y="skills/$d/agents/openai.yaml"
  [ -f "$y" ] || { note FAIL "$y missing"; continue; }
  out=$(python3 - "$y" "$d" <<'PY'
import sys, yaml
path, skill = sys.argv[1], sys.argv[2]
i = (yaml.safe_load(open(path)) or {}).get("interface") or {}
errs = []
if not i.get("display_name"):
    errs.append("display_name missing")
sd = i.get("short_description", "")
if not 25 <= len(sd) <= 64:
    errs.append("short_description %d chars, want 25-64" % len(sd))
dp = i.get("default_prompt", "")
if ("$" + skill) not in dp:
    errs.append("default_prompt must name the skill as $" + skill)
print("; ".join(errs))
PY
)
  [ -z "$out" ] || note FAIL "$y: $out"
done
note ok "openai.yaml valid"

echo "--- no legacy layout strings"
LEGACY='(\.\./)?_(kb|scripts|templates)/|\.claude/skills/[a-z_]|check-docs\.sh'
if grep -rnE "$LEGACY" skills >/dev/null 2>&1; then
  grep -rnE "$LEGACY" skills | sed 's/^/  FAIL   /'; fail=1
else note ok "none"; fi

echo "--- no stray relative escapes"
# `../<skill>/...` is the portable cross-skill form; anything else escaping the skill is a bug.
if grep -rn '\.\./' skills | grep -vE '\.\./('"$SK_RE"')/' >/dev/null 2>&1; then
  grep -rn '\.\./' skills | grep -vE '\.\./('"$SK_RE"')/' | sed 's/^/  FAIL   /'; fail=1
else note ok "only ../<skill>/ forms"; fi

echo "--- dogfooding symlinks resolve"
for base in .agents/skills .claude/skills; do
  for d in $SKILLS; do
    [ -d "$base/$d" ] || { note FAIL "$base/$d does not resolve"; continue; }
    [ -f "$base/$d/SKILL.md" ] || note FAIL "$base/$d/SKILL.md missing through the symlink"
  done
done
note ok "both clients load this repo's own skills"

echo "--- acsl-verify stays a router"
extra=$(find skills/acsl-verify -type f ! -name SKILL.md ! -name openai.yaml)
[ -z "$extra" ] && note ok "SKILL.md only" || note FAIL "acsl-verify bundles files: $extra"

echo "--- leaf skills route back to the loop owner"
for d in acsl-spec verifiable-c frama-c-wp wp-coq; do
  grep -q 'acsl-verify' "skills/$d/SKILL.md" || note FAIL "skills/$d/SKILL.md never points back to acsl-verify"
done
note ok "all leaf skills route back"

echo "--- the two env.sh copies are identical"
cmp -s skills/frama-c-wp/scripts/env.sh skills/wp-coq/scripts/env.sh \
  && note ok "byte-identical" || note FAIL "env.sh copies have diverged"

# ---------------------------------------------------------------- content invariants
echo "--- RTE policy has not drifted back to a hard requirement"
# The two unsigned checks are a default with one documented exception. That is a multi-site
# fact, so assert that every file naming the flags also carries the qualifier.
for f in $FILES; do
  grep -q -- '-warn-unsigned-' "$f" || continue
  grep -qE 'hostile-c|by default' "$f" \
    || note FAIL "$f names the unsigned flags with no 'by default' or hostile-c pointer"
done
note ok "all sites qualified"

echo "--- no machine-specific absolute paths"
if grep -rnE '^[^#]*(/home/[a-z]+/|/tmp/claude-)' skills/*/scripts/*.sh skills/*/SKILL.md >/dev/null 2>&1; then
  grep -rnE '^[^#]*(/home/[a-z]+/|/tmp/claude-)' skills/*/scripts/*.sh skills/*/SKILL.md | sed 's/^/  FAIL   /'
  fail=1
else note ok "none"; fi

echo "--- toolchain is resolved, not pinned"
grep -qE 'switch=[0-9]+\.[0-9]+' skills/*/scripts/*.sh && note FAIL "a script pins an opam switch name"
note ok "env.sh resolves it"

echo "--- scripts parse"
for f in skills/*/scripts/*.sh tools/*.sh; do bash -n "$f" || note FAIL "$f"; done
note ok "all parse"

echo "--- any frama-c call outside the wrappers carries the env preamble"
for f in skills/*/SKILL.md skills/*/references/*.md; do
  grep -q '^frama-c ' "$f" || continue
  grep -qE 'opam env|scripts/env\.sh' "$f" || note FAIL "$f calls frama-c directly with no preamble"
done
note ok "checked"

# ---------------------------------------------------------------- external validators
echo "--- agentskills.io validator"
# The `skills-ref` package installs its CLI as `agentskills`.
if command -v agentskills >/dev/null 2>&1; then V=(agentskills)
elif command -v uv >/dev/null 2>&1; then V=(uv tool run --quiet --from skills-ref agentskills)
else V=(); fi
if [ ${#V[@]} -eq 0 ]; then note skip "agentskills not available (pip install skills-ref)"
else
  bad=0
  for d in $SKILLS; do
    out=$("${V[@]}" validate "skills/$d" 2>&1) \
      || { note FAIL "agentskills: skills/$d: $(echo "$out" | tail -3 | tr '\n' ' ')"; bad=1; }
  done
  [ "$bad" = 0 ] && note ok "all five validate"
fi

echo "--- Codex skill validator"
CV="$HOME/.codex/skills/.system/skill-creator/scripts/quick_validate.py"
if [ -f "$CV" ]; then
  bad=0
  for d in $SKILLS; do
    out=$(python3 "$CV" "skills/$d" 2>&1) \
      || { note FAIL "codex validate: skills/$d: $(echo "$out" | tail -2 | tr '\n' ' ')"; bad=1; }
  done
  [ "$bad" = 0 ] && note ok "all five valid for Codex"
else note skip "Codex skill-creator not installed"; fi

echo "--- plugin manifest"
if command -v claude >/dev/null 2>&1; then
  out=$(claude plugin validate . 2>&1) && note ok "claude plugin validate passes" \
    || note FAIL "claude plugin validate: $(echo "$out" | tail -3 | tr '\n' ' ')"
else note skip "claude not on PATH"; fi

# ---------------------------------------------------------------- slow checks
if [ "$QUICK" = 0 ]; then
  . skills/frama-c-wp/scripts/env.sh

  echo "--- documented prover versions match the installed ones"
  for v in $(grep -oE '(Alt-Ergo|CVC5|CVC4|Z3|Coq) [0-9][0-9.]*' \
             skills/frama-c-wp/references/toolchain.md | sort -u); do
    frama-c -wp-list-provers 2>/dev/null | grep -qiF "$(echo "$v" | tr -d ' ')" \
      || frama-c -wp-list-provers 2>/dev/null | grep -qi "$(echo "$v" | cut -d' ' -f1).*$(echo "$v" | cut -d' ' -f2)" \
      || note FAIL "toolchain.md claims '$v' but -wp-list-provers disagrees"
  done
  note ok "versions match"

  echo "--- templates typecheck (this gap shipped a broken template once)"
  t=$(mktemp -d)
  cp skills/acsl-spec/assets/* "$t"/ 2>/dev/null
  cp skills/frama-c-wp/assets/lemma-function.c "$t"/ 2>/dev/null
  tpl=0
  ( cd "$t" && cp contract.h example.h 2>/dev/null
    printf '#include "logic.acsl"\nint main(void){return 0;}\n' > la.c
    for c in contract.h la.c loop.c lemma-function.c; do
      out=$(frama-c -pp-annot -cpp-extra-args="-I." "$c" 2>&1 \
            | grep -iE 'unbound|Ignoring (global annotation|specification)|User Error')
      [ -z "$out" ] || { echo "  FAIL   $c: $(echo "$out" | head -1)"; exit 1; }
    done ) || { fail=1; tpl=1; }
  rm -rf "$t"
  [ "$tpl" = 0 ] && note ok "templates typecheck"
fi

echo
[ "$fail" = 0 ] && { echo "check-docs: OK"; exit 0; }
echo "check-docs: FAILURES above"; exit 1
