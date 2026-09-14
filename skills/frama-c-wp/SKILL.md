---
name: frama-c-wp
description: Run and debug Frama-C/WP proofs of C code. Exact command lines, prover selection (Alt-Ergo, CVC4, CVC5, Z3, Coq), memory-model choice, RTE generation, smoke tests, the proof cache, single-goal drill-down, and a triage table mapping WP's exact error and warning text to a concrete fix. Use when WP goals time out or return Unknown, when WP aborts with a User Error, when a proof result looks suspicious, or when asked how to run WP or why a proof fails.
license: MIT
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/wp.sh *) Bash(${CLAUDE_SKILL_DIR}/scripts/wp-smoke.sh *) Bash(${CLAUDE_SKILL_DIR}/scripts/wp-goal.sh *)
---

# Running and debugging WP

**Requires** Frama-C 33 with the WP plugin, Why3, and Alt-Ergo (CVC5 and Z3 recommended),
reachable through opam or on `PATH`, plus bash.

## Run it

Always through the wrapper — it applies the environment preamble, the verified flag set, and a
soundness scan of the output.

Paths here are relative to this skill's own directory, which is normally **not** your
shell's working directory. Resolve them against the skill directory and run the absolute
path (in Claude Code, `${CLAUDE_SKILL_DIR}` expands to it).

```sh
scripts/wp.sh file.c                  # standard run
scripts/wp.sh -t 20 -I include file.c
scripts/wp.sh -f myfunc file.c        # one function
```

Exit codes: `0` proved and clean · `1` unproved goals · `2` WP aborted · `3` **proved but
untrustworthy** — soundness findings present.

Then the vacuity gate. Not optional:

```sh
scripts/wp-smoke.sh file.c
```

A green run is not a finished proof. The `acsl-verify` skill owns the done criteria; `wp.sh`
exit 0 still needs `wp-smoke.sh` before anything can be reported as verified.

## Read the result correctly

WP degrades by polarity: an unsupported construct in a *goal* becomes `False`, in a
*hypothesis* it is dropped. So `not implemented` noise around a proved goal is harmless.
**Only the silent tier can lie**, and every entry in it is greppable:

```
might be unsound · not yet supported (skipped) · Missing RTE guards
interpreted as reads nothing · using unguarded behavior assigns
using complete behaviors assigns · Memory model hypotheses for function · Failed smoke-test
```

WP also emits two `Skipped RTE guards:` lines on **every** run, for pointer alignment and
function-pointer validity. They are not findings by themselves — they matter only if the code
really does unaligned access or calls through a function pointer, and `wp.sh` escalates the
second one only when a `Missing 'calls'`/`Unknown callee` diagnostic co-occurs. Exact strings:
`references/limitations.md` §6.

Worked example of why this matters: a statement contract emits
`Statement specifications not yet supported (skipped).` and the function then reports
**4/4 goals proved** — the annotation was silently discarded. Never report success on a run
`wp.sh` exited 3 on.

**Frama-C's own exit status is not a verdict.** Verified: a function returning 7 under
`ensures \result == 42` gives `Proved goals: 3 / 4` and exit `0`, so a gate written as
`frama-c ... && echo OK` can never fail. Parse `Proved goals: n / m` and compare the halves —
and scan for the silent tier above before trusting a full count. That is what `wp.sh` does,
and why its exit codes mean something when Frama-C's do not.

## When a goal fails

Full procedure in `references/triage.md`. The short form, cheapest first:

```
0. spec is wrong or too weak   <- the answer most of the time
1. cheap prover work           -t 20, -wp-split-conj, try z3 / cvc5
2. auto-active                 guiding assert; instantiate a lemma
3. lemma function              encode the induction in C  (preferred over Coq)
4. WP tactics                  -wp-auto / -wp-tactic, script in <session>/script/
5. Coq                         the wp-coq skill, last resort
```

Start at 0 by dumping the goal:

```sh
scripts/wp-goal.sh -f myfunc -p invariant-name -r file.c
```

Read `Assume` (what WP believes) against `Prove` (the obligation). A fact missing from
`Assume` means the invariant or precondition that should have supplied it is too weak — that
is the fix, not a longer timeout.

`Unknown` returned quickly means a missing hypothesis. `Timeout` after the full budget means
the goal is too big or nonlinear. `Invalid` means the property is genuinely false.

This drill-down needs **named clauses** (`requires valid:`, `loop invariant bound:`). Naming
is a functional requirement, not style — `-wp-prop` is how you isolate one goal out of a
hundred.

## Provers

| Prover | Strength |
|---|---|
| Alt-Ergo | quantifiers, arrays, the memory model — first choice |
| CVC5 | quantifiers + arithmetic; often wins where Alt-Ergo stalls |
| Z3 | nonlinear arithmetic, bitvectors, unrolling recursive definitions |
| CVC4 | cheap second opinion |
| Coq | induction; manual, last resort — see the `wp-coq` skill |

Confirm detection with `frama-c -wp-list-provers` before trusting a run. A prover Why3 has not
detected is a silent no-op when you name it, not an error — see `references/toolchain.md`.

## Memory models

Default `Typed` is correct for nearly everything. Do not change it to make a warning go away.
`+cast` was verified **not** to silence the incompatible-pointer warning and **not** to help
byte punning. `+ref`/`+caveat` inject unproved separation hypotheses — if you use them, add
`-wp-check-memory-model`. Detail in `references/memory-models.md`.

## Reference

| Need | Read |
|---|---|
| a goal failed and you have its text or a dump | `references/triage.md` |
| deciding whether a "proved" result can be trusted | `references/limitations.md` |
| flags, prover setup, cache, session layout | `references/toolchain.md` |
| the spec needs a fact SMT cannot reach | `references/auto-active.md`, `assets/lemma-function.c` |
| a warning tempts you to change `-wp-model` | `references/memory-models.md` |
| the C itself is the obstacle | the `verifiable-c` skill |
| the annotation is the obstacle | the `acsl-spec` skill |
