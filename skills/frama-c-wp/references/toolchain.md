# Toolchain

## Environment preamble (mandatory)

Nothing works without this: `frama-c` lives in an opam switch, and `cvc5` is usually not in
opam at all. The wrapper scripts apply it for you — use them rather than typing flags by hand.
To do it in a shell of your own:

```sh
. scripts/env.sh
```

`env.sh` resolves the toolchain in this order:

1. `$FRAMAC_SWITCH` if you set it,
2. otherwise the opam switch that actually contains `frama-c` (current switch preferred),
3. otherwise whatever `frama-c` is already on `PATH` — no opam involved.

It then prepends `$FRAMAC_EXTRA_BIN` (default `~/.local/bin`) so a solver installed outside
opam is visible to Why3. Nothing pins a switch name, so the skillset moves between machines
unchanged; if no `frama-c` can be found it fails loudly rather than half-working.

## Versions this was verified against

| Tool | Version |
|---|---|
| Frama-C | 33.0 (Arsenic) |
| Why3 | 1.8.2 |
| Alt-Ergo | 2.6.3 |
| CVC4 | 1.8 |
| CVC5 | 1.3.4 |
| Z3 | 5.1.0 |
| Coq | 8.20.1 (plus `why3-coq`, mandatory for `-wp-prover coq`) |

Confirm the provers are visible before trusting a run:

```sh
frama-c -wp-list-provers
```

**A prover Why3 has not detected is a silent no-op, not an error** — `-wp-prover CVC5` on an
install where Why3's version regexp does not match the installed CVC5 simply does nothing, and
the run looks like the goals were hard. Check this list first when a prover seems useless.
Re-running `why3 config detect` after installing a solver is what registers it.

## Canonical flag set

```
-pp-annot -no-unicode
-wp -wp-rte -warn-unsigned-overflow -warn-unsigned-downcast
-wp-model Typed
-wp-split
-wp-timeout 2 -wp-par <cores>
-wp-prover alt-ergo -wp-prover cvc5 -wp-prover z3
-wp-session <dir> -wp-interactive=batch
-wp-report-json <file>
```

Why each one is not optional:

- `-pp-annot` — runs the preprocessor **inside** annotations. Without it, `#include` of a
  shared `.acsl` logic header silently does nothing.
- `-wp-rte` — generates the overflow / validity / division goals. Without it none exist and a
  100% score means nothing.
- `-warn-unsigned-overflow -warn-unsigned-downcast` — RTE skips unsigned checks by default, so
  without these two, unsigned wraparound and narrowing are never checked. On by default; the
  only supported exception is a codebase whose idioms make them false by construction — see
  `verifiable-c/references/hostile-c.md`, which owns that carve-out and the way a reduced
  run has to announce itself.
- `-wp-model Typed` — the default, and the only fully sound general-purpose model.
- `-wp-split` — splits conjunctive goals so a failure points at one clause.
- `-wp-session` — persists the proof cache and any Coq/tactic scripts. Reuse the same dir
  across runs or every iteration re-proves everything.
- `-wp-report-json` — machine-readable status. Branch the loop on this, not on the log text.
- `-wp-par` — prover parallelism. `wp.sh` defaults to `nproc`; a hand-tuned lower value
  measurably loses on a many-core machine.

## Proof cache

Cache entries live in `<session>/cache/`. Modes for `-wp-cache`:

| Mode | Effect |
|---|---|
| `update` | use cache, run missing goals, write results back (default) |
| `replay` | use cache, run missing goals, **do not** write back |
| `rebuild` | ignore cache, re-prove, overwrite |
| `none` | no cache at all |
| `cleanup` | `update` plus garbage-collect stale entries |
| `offline` | replay from cache only; **never invokes a prover**. A goal not in the cache fails |

`FRAMAC_WP_CACHEDIR` sets a global cache dir outside the session. A prover or Frama-C upgrade
must invalidate the cache; hashing the toolchain version into a stamp file is the usual way to
force that automatically.

**A cache key depends on the analysis context, so populate it the way you will consume it.**
Measured: a cache built by one 31-file run replayed `strcmp` at 215/236 file-by-file, and at
236/236 once that file had been proved on its own. Nothing warns you — the misses look exactly
like goals that were never proved.

`offline` is what makes a checkout checkable without provers installed, and it is the only
mode that proves the committed cache is actually complete. Whether to commit it at all is a
judgement call `verifiable-c/references/project-layout.md` owns; if you do, prune it first —
rebuild from the functions you claim as proved and drop every entry that does not record a
proof. Measured on a mid-size project, pruning cut the cache from 4920 files and 25 MB to
1933 entries and 11 MB.

## Session directory layout

```
<session>/
├── cache/                     content-hashed prover results
├── interactive/<goal>.v       hand-written Coq proofs   (-wp-prover coq)
├── script/<goal>.json         WP tactic scripts         (-wp-prover tip)
└── reports/<fn>.json          -wp-report-json baselines, one per function
```

`<goal>` is the proof-obligation id: `lemma_<name>` for a lemma, `typed_<fn>_<clause>` for a
function goal.

## Invoking the scripts

Paths in this skill are relative to the skill's own directory: `scripts/wp.sh`,
`scripts/env.sh`. In Claude Code, `${CLAUDE_SKILL_DIR}` expands to that directory, so
`${CLAUDE_SKILL_DIR}/scripts/wp.sh file.c` works from any working directory.

In a plain shell, resolve the directory holding the skill folders once and reuse it:

```sh
SKILLS=$HOME/.claude/skills            # or <project>/.claude/skills, or a checkout
"$SKILLS/frama-c-wp/scripts/wp.sh" file.c
"$SKILLS/wp-coq/scripts/coq-iter.sh" .wp-session/interactive/<goal>.v
```

Each script resolves its own directory, so it can be called by any path, from any cwd, or
through a symlink.

**Each skill is self-contained, but install the set together.** A skill's own
`references/`, `scripts/` and `assets/` always resolve. Pointers that name another skill
(`verifiable-c/references/hostile-c.md`) assume the five skill folders sit side by side —
which is what copying the whole `skills/` directory gives you.

## Scripts

| Script | Use |
|---|---|
| `scripts/wp.sh` | the standard run: preamble, verified flags, soundness scan. `-S` folds the smoke pass into the same invocation (~20% faster than running both) |
| `scripts/wp-smoke.sh` | the vacuity gate on its own |
| `scripts/wp-goal.sh` | drill into one function or clause; `-r` dumps the raw VC |
| `wp-coq/scripts/coq-iter.sh` | fast headless Coq typecheck |

All take `-I DIR` (repeatable) for annotation includes and `-j N` for prover parallelism.

**Cache defaults differ on purpose.** `wp.sh` uses `-wp-cache update`, and repeat full-file
runs measurably get faster. `wp-goal.sh` uses `-wp-cache none`: for a single function whose
goals are already sub-second, the content-hash lookup costs more than re-proving. Override
either with `-C`.

## Useful one-off options

| Option | Use |
|---|---|
| `-wp-fct f` | only function `f` |
| `-wp-prop=name` | only the clause named `name` (needs named clauses) |
| `-wp-fct-timeout f:30` | per-function timeout |
| `-wp-print` / `-wp-no-qed` | dump the raw VC, unsimplified |
| `-wp-status` | list pending goals only |
| `-wp-smoke-tests` | vacuity gate — see `references/limitations.md` B-5 |
| `-wp-list-provers` | check prover detection |
| `-wp-tactic '?'` / `-wp-auto '?'` | list the registered tactics / strategies |
| `-wp-msg-key prover` | show the exact prover command line |
| `-wp-proof-trace` | keep prover output for valid goals |
