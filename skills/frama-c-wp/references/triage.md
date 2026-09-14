# Triage: a goal did not prove

Work top to bottom. Each step is cheaper than the one after it. Do not skip to a longer
timeout — that is step 1 of 5 and rarely the real problem.

## First: is it actually a proof problem?

| Result | Meaning | Where to go |
|---|---|---|
| `Timeout` | prover ran out of time | ladder below |
| `Stepout` | prover ran out of steps (`-wp-steps`) | ladder below |
| `Unknown` | prover **returned** without deciding — usually a missing hypothesis, not slowness | step 0, then step 2 |
| `Invalid` / counter-example | the property is **false** for some state | step 0 — fix the code or the spec |
| `Failed` + `Failed smoke-test` | vacuity, not a proof failure | `references/limitations.md` B-5 |
| `Degenerated` | annotation used an unsupported construct → goal is `False` | `references/limitations.md` tier A |
| `Missing` | no prover was asked, or a script is absent | check `-wp-prover` |

`Unknown` arriving fast is the strongest signal that a fact is missing from the context.
A `Timeout` after the full budget usually means the goal is too big or nonlinear.

## Step 0 — is the specification wrong or too weak?

The most common cause by a wide margin. Before touching prover settings, dump the goal:

```sh
scripts/wp-goal.sh -f <function> -p <clause-name> -r <file.c>
```

Read the two halves:

- **`Assume`** — everything WP believes at that point.
- **`Prove`** — the obligation.

If a fact you were relying on is absent from `Assume`, then the `requires`, `loop invariant`
or callee `ensures` that should have supplied it is missing or too weak. That is the fix.

Checklist, in order of how often it is the answer:

1. **Loop invariant too weak.** It must be true on entry, preserved by the body, and — with the
   negated loop condition — strong enough to imply the postcondition. All three, or it is not
   an invariant. A loop invariant that only bounds the index proves nothing about the result.
2. **`loop assigns` missing or too narrow.** Anything not listed is havocked; anything listed
   but not actually assigned is fine. Missing it entirely means "assigns everything".
3. **`assigns` on a callee missing.** `Missing assigns clause (assigns 'everything' instead)` —
   the caller then knows nothing survived the call.
4. **Precondition too weak.** Overflow goals need explicit bounds: `requires n <= INT_MAX - 1;`.
5. **Aliasing not excluded.** Two pointer parameters may overlap unless you say otherwise. Add
   `requires \separated(a + (0..n-1), b + (0..m-1));`.
6. **Postcondition means something other than you think.** Especially with `\at`/`\old` — see
   `acsl-spec/references/memory-labels.md`. A `!` in front of an integer-valued term is the
   quiet one: in ACSL it means `== 0`, so `!cmp(a, b)` asserts the comparison is *equal*. It
   typechecks and reads like natural-language negation.
7. **The fact is present but the pointer is not reconstructible.** Everything needed is in
   `Assume`, yet the goal wants `p == q + (p - q)`, which WP does not derive. Carry a ghost
   index, or state the fact in the callee — `references/limitations.md` C-11.
8. **A lemma you are leaning on was never proved.** WP hands you every lemma in scope as a
   hypothesis, discharged or not. Check that the one carrying your argument actually proves;
   if it is false, goals around it have been passing on its strength —
   `references/limitations.md` B-18.

## Step 1 — cheap prover work

```sh
scripts/wp.sh -t 20 file.c              # raise timeout
scripts/wp.sh -x "-wp-split-conj" file.c # split conjunctions harder
scripts/wp.sh -P z3 file.c               # a different prover, one at a time
```

Provers have genuinely different strengths — the table is in the `frama-c-wp` skill body.
`-wp-run-all-provers` runs them all instead of stopping at the first success: useful to learn
which one owns a goal, wasteful as a default.

If a single function is the problem: `-wp-fct-timeout myfunc:60`.

## Steps 2–4 — auto-active, lemma functions, tactics

The solver is not searching your whole context; it works from the hypotheses in one VC, so a
true lemma that is never instantiated is invisible to it. Three tiers put the fact where it
will be seen, and `references/auto-active.md` is the canonical description of all three:

2. **Guiding `assert`** placed where the fact is needed. It becomes a goal and then a
   hypothesis. Bisecting a function with asserts is also how you find which step fails.
   `check` adds the goal without the hypothesis; `admit` the hypothesis without the goal, and
   every `admit` left behind is an unproved assumption (`references/limitations.md` B-10).
3. **Lemma function** — a C function whose contract *is* the lemma and whose body *is* the
   proof. WP's loop-invariant machinery does the induction SMT cannot. Preferred over Coq.
4. **WP tactics** — optional. List what is registered with `-wp-tactic '?'` and
   `-wp-auto '?'`; an unregistered name is silently ignored.

## Step 5 — Coq

Only for goals that genuinely need induction over a recursive definition and where a lemma
function could not be expressed — typically because the lemma quantifies over ACSL labels.
See the `wp-coq` skill.

## Symptom index

| WP says | Cause | Fix |
|---|---|---|
| `Missing assigns clause (assigns 'everything' instead)` | a callee or loop has no `assigns` | add it — every function and every loop |
| `Missing RTE guards` | `-wp-rte` not passed | pass it; without it the score is meaningless |
| `annot:missing-spec <header>:<line>` | callee's contract is in the `.c`, not the header | move it to the header — callers in other units see only the prototype |
| `Missing 'calls' for default behavior` / `Unknown callee` | indirect call with no `//@ calls` | add `//@ calls f, g;` at the call site |
| `Missing terminates clause on call to f` | callee has no `terminates` | add `terminates \true;` (or the real condition) |
| `Missing decreases clause on recursive function f` | recursion without a measure | add `decreases <expr>;` |
| `Cast with incompatible pointers types` | pointer type punning | remove the cast; `assigns` has already degraded |
| `Accessing union fields with Typed model might be unsound` | union member access | do not spec across members; see `references/limitations.md` B-1 |
| `Statement specifications not yet supported (skipped)` | statement contract | extract into a function — **the annotation was dropped and goals still "prove"** |
| `Generalized invariant not yet supported (skipped)` | statement-level `invariant` | use `loop invariant` or `assert` |
| `No definition for 'f' interpreted as reads nothing` | declared-only logic function | give it a body or a `reads` clause |
| `No default assigns clause, using …` | per-behavior `assigns` only | add a default-behavior `assigns` |
| `Memory model hypotheses for function 'f'` | `+ref`/`+caveat` model | add `-wp-check-memory-model`, or use plain `Typed` |
| `Non-natural loop detected` | `goto` back-edge | rewrite as a structured loop — WP skipped the function |
| `Failed smoke-test` | vacuous spec or dead code | fix the spec, never the smoke test |
| `... not implemented yet` in an annotation | unsupported ACSL construct | `references/limitations.md` tier A, re-express it |

## Do not do these

- **Do not weaken a postcondition to make it prove.** That is deleting the property, not
  verifying it. If the property is genuinely not what you want, change it deliberately and say so.
- **Do not add `admit` to close a goal** unless you are recording a known, tracked assumption.
- **Do not switch to `+cast` to silence a cast warning.** Verified: it does not silence the
  warning and did not help the punning probe.
- **Do not drop `-wp-rte` to get a green run.**
- **Do not accept 100% proved without `wp-smoke.sh`.** A contradictory `requires` proves
  everything — verified.
