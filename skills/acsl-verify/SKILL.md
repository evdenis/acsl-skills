---
name: acsl-verify
description: Entry point for any ACSL/Frama-C/WP verification work on C code. Use when asked to verify, prove or formally check C, to "add specs and prove it", to make an existing proof pass, or when it is unclear whether a failing proof is a specification problem or a prover problem. Owns the annotate-run-triage-strengthen loop, the escalation ladder from SMT through lemma functions to Coq, and the definition of done. Routes to acsl-spec, frama-c-wp, verifiable-c and wp-coq.
license: MIT
---

# Verifying C with Frama-C/WP

**Requires** the `acsl-spec`, `frama-c-wp`, `verifiable-c` and `wp-coq` skills installed
alongside this one, and Frama-C 33 with the WP plugin.

## The loop

Verification is a loop, not a writing task. Never stop after annotating.

```
write/fix annotations  ->  wp.sh  ->  exit 0: wp-smoke.sh, done
                 ^                    exit 1/2/3: triage, then back up
```

## Start here

Paths here are relative to this skill's own directory, which is normally **not** your
shell's working directory. Resolve them against the skill directory and run the absolute
path (in Claude Code, `${CLAUDE_SKILL_DIR}` expands to it).

```sh
../frama-c-wp/scripts/wp.sh file.c         # -I dir, -t secs, -f func
../frama-c-wp/scripts/wp-smoke.sh file.c   # only after wp.sh exits 0
```

`frama-c-wp/scripts/wp.sh` applies the environment preamble, the verified flag set and a
soundness scan of the output. Options and output reading: the `frama-c-wp` skill.

| Exit | Meaning | Next |
|---|---|---|
| 0 | proved, no soundness findings | run `wp-smoke.sh` |
| 1 | unproved goals | triage — the `frama-c-wp` skill |
| 2 | WP aborted (`User Error`) | restructure the C — the `verifiable-c` skill |
| 3 | **proved but untrustworthy** | fix the finding first — the result is not evidence |

## Done

All five, or it is not done. This list is the canonical one; other skills point here.

1. 100% of goals proved.
2. RTE was on — `-wp-rte`, with `-warn-unsigned-overflow -warn-unsigned-downcast` unless the
   codebase has a documented reason to drop them
   (`verifiable-c/references/hostile-c.md`; `wp.sh -U`, which prints `REDUCED`). `wp.sh` does
   this; never drop a check just to get a green run.
3. `wp-smoke.sh` reports no vacuity.
4. No tier-B strings in the output (`wp.sh` exits 3 if there are).
5. Every function carries `terminates`, `exits` and `assigns`.

A goal count that went **down** after removing a false lemma or invariant is a correct
outcome, not a regression — those goals were leaning on it. Report the drop and name what was
false (`frama-c-wp/references/limitations.md` B-18).

Report honestly against this list. If part of the file could not be proved, say which
functions and why, rather than reporting the rest as success.

## Why the gates exist

A goal count on its own is not evidence. Each of these is verified behaviour:

- A statement contract emits `Statement specifications not yet supported (skipped).` — the
  annotation is discarded and the function then reports **4/4 goals proved**.
- Union field access warns `might be unsound` and proves anyway.
- `requires n > 0 && n < 0;` proves `\result == 42` for a function that returns 0. Only
  `-wp-smoke-tests` catches it.
- Without `-wp-rte`, no overflow, validity or division goal is ever generated.

WP is otherwise well behaved: an unsupported construct in a *goal* becomes `False`, in a
*hypothesis* it is dropped. So `not implemented` noise around a proved goal is harmless. Only
the silent tier lies, and every entry in it is greppable — which is what `wp.sh` checks.

## Escalation ladder

Cheapest first. Do not jump to step 5.

| Step | Action | Where |
|---|---|---|
| 0 | the spec is wrong or too weak — **usually the answer** | `acsl-spec`, `frama-c-wp/references/triage.md` |
| 1 | raise timeout, `-wp-split-conj`, try z3 / cvc5 | the `frama-c-wp` skill |
| 2 | guiding `assert`; instantiate a lemma | `frama-c-wp/references/auto-active.md` |
| 3 | lemma function — encode the induction in C | `frama-c-wp/references/auto-active.md` |
| 4 | WP tactics, `-wp-auto` / `-wp-tactic` | `frama-c-wp/references/auto-active.md` |
| 5 | manual Coq proof | the `wp-coq` skill |

Steps 2–3 are the preferred route. A lemma function proved 20/20 goals on exactly the
property that, written as a plain `lemma`, times out on every SMT prover and needs a
hand-written Coq script.

## Routing

| Situation | Skill |
|---|---|
| write or fix annotations | `acsl-spec` |
| run WP, read a failure, choose a prover | `frama-c-wp` |
| WP aborted, or the C shape is the problem | `verifiable-c` |
| writing new C intended for proof | `verifiable-c` |
| a goal genuinely needs induction and step 3 could not express it | `wp-coq` |

## Retrofitting onto unannotated code

Do not start with full functional specs. Run `wp.sh` with RTE on and **no** contracts first —
what fails is the real runtime-error risk, and that output is worth having on its own. Then add
only the `requires`/`assigns` that discharge those goals, and add functional postconditions
last, innermost functions first (a caller cannot be proved before its callees have contracts).

Some functions need the C restructured before they can be specified at all — route those to
`verifiable-c` and say so explicitly rather than writing a contract that will never prove.
Refactoring order: `verifiable-c/references/style.md`. Legacy-specific guidance:
`verifiable-c/references/hostile-c.md`.
