# What WP 33.0 cannot verify

Read this before writing a contract or believing a proof.

Provenance: **[v]** reproduced against Frama-C 33 · **[src]** read in WP's own OCaml source ·
**[doc]** the ACSL 1.24 manual or Frama-C's documentation.

## 0. The trust model — read this first

WP degrades **by polarity**, so an unsupported construct almost never fabricates a `Valid` [src]:

| Position | What WP does | Marked | Effect |
|---|---|---|---|
| Goal (`ensures`, `assert`) | falls back to `False` | `(Degenerated)` | goal becomes unprovable. **Safe.** |
| Hypothesis (`requires`, `assumes`) | dropped | `(Stronger)` | goal gets harder. **Safe.** |
| Sub-term | value made opaque | `(Stronger)` | less information. **Safe.** |
| `assigns` it cannot read | assigns everything | — | caller learns nothing. Safe but proof-killing. |

**The rule that follows:** `not implemented` noise around a `Valid` result is *not* a soundness
problem — the goal simply got harder or impossible. **Tier B is the only tier where "proved"
can be a lie.** Police tier B by grep; ignore tier A/C noise when the goal proved anyway.

## 1. Classification procedure

Run on every WP invocation; `scripts/wp.sh` does it automatically. Grep the output against
the classifier in §6 and take the worst tier present. **Tier A** means the goal count from
this run is meaningless — stop and restructure. **Tier B** means a `Valid` is not evidence.
**Tier C** means apply a technique. A clean run at 100% still needs `wp-smoke.sh` before it
counts as done (B-5).

## 2. Tier A — WP aborts or refuses

| # | Construct | Symptom | Fix |
|---|---|---|---|
| A-1 | Irreducible CFG: `goto` back-edge, Duff's device | `Non-natural loop detected in function 'f'.` + `This case is not supported yet (skipped verification).` — **hard User Error, whole function skipped** [v][src] | Rewrite as `while`/`for`/`do-while`. Forward `goto` to one cleanup label is fine. |
| A-2 | Recursive entry point | `Main entry point function 'f' is (potentially) recursive.` [src] | Non-recursive wrapper + recursive worker. |
| A-3 | Logic cast in a term: `(struct S)`, `(union U)`, `(float)`, `(T*)`, `(T[n])`, `(T[])`, sized integer | `Logic cast from/to ... not implemented yet`, 10 variants [src] | Use `integer`/`real` so no cast is needed; or a logic function; or bind with `\let` before casting. |
| A-4 | `\lambda` | `Lambda-functions not yet implemented` [src] | Named `logic`/`predicate` with explicit parameters. |
| A-5 | `\let` binding a set or complex term | `Complex let-binding not implemented yet` [src] | Inline it, or lift to a logic function taking the parts as arguments. |
| A-6 | `\typeof`, `\type(T)`, `\subtype` | `Type tag not implemented yet` [src] | C has no runtime types. Use a ghost `int` discriminant. |
| A-7 | `model` variables and fields | `Model field` not yet implemented [src][doc] | Use a `//@ ghost` field or ghost global. |
| A-8 | `\inter(...)` in `assigns` | `Intersection in assigns not implemented yet` [src] | Write the explicit range: `assigns a[lo..hi];`. `\union` **is** supported. |
| A-9 | Pointer sets / region tsets as values | `Set of pointers not yet implemented`, `T-Set of regions not yet implemented`, `T-Set of values not yet implemented` [src] | Quantify instead: `\forall integer k; lo <= k < hi ==> P(a[k])`. |
| A-10 | Set comprehension used as a value | `Concretization for comprehension sets not implemented yet` [src] | Quantify instead. |
| A-11 | String literal in a spec | `String constants not yet implemented` [src] | Try `-wp-literals`; otherwise copy into a named `static const char[]` and spec that. |
| A-12 | `\aligned(p,n)` | `\aligned not yet implemented` [v][src]; RTE guards also skipped [v] | Delete it. Alignment becomes a documented, unverified assumption. |
| A-13 | `\valid_function(f)` | `\valid_function not yet implemented` [v][src] | Use `//@ calls f, g;` at each indirect call site (C-4). |
| A-14 | `malloc`/`free`, `\fresh`, `\allocable`, `\freeable`, `\dangling` | `Allocation, initialization and danglingness not yet implemented` [v][src]; the manual is explicit that WP cannot work with dynamic allocation [doc] | Caller-allocated `T *buf, size_t n` in the verified core; allocation lives in the unverified shell. |
| A-15 | `extern T a[];` in `\valid` | `Validity of unsized-array not implemented yet` [src] | Declare a size. `-wp-extern-arrays` invents one — that makes it tier B. |
| A-16 | C++ `throw`/`try` | `RefUsage: throw/try-catch not implemented` [src] | The verified layer must be exception-free C. |

**Correction to a widespread belief:** `\initialized` **is** implemented [v] — only allocation
and dangling share A-14's message. `\valid`, `\valid_read`, `\separated`, `\at`, `\union` and
`\subset` are implemented too.

## 3. Tier B — silent: "proved" may be a lie

The only tier that can mislead you. Every row is detectable by grep; none by the goal count.

| # | Construct | Detection | Kind | Fix |
|---|---|---|---|---|
| B-1 | Union field access | `Accessing union fields with Typed model might be unsound.` — **goals still report proved** [v] | unsound | Do not spec across union members. Tagged struct instead. `-wp-model Bytes` is the only sound option (experimental, slow). |
| B-2 | Statement contract `/*@ requires..ensures..*/ { … }` | `Statement specifications not yet supported (skipped).` — **verified: annotation vanishes and the function reports 4/4 proved** [v][src] | dropped | Extract the block into a function with a real contract. |
| B-3 | Statement-level `/*@ invariant … */` | `Generalized invariant not yet supported (skipped).` [src] | dropped | Use `loop invariant`, or an `assert` at that point. |
| B-4 | No `-wp-rte` | `Missing RTE guards` [v][src] | dropped | No overflow, validity or division goal is ever generated. Always pass it. The two unsigned checks are on by default and dropped only for a codebase whose idioms make them false by construction — `verifiable-c/references/hostile-c.md` owns that carve-out and the record it has to carry. |
| B-5 | Vacuous spec: unsatisfiable `requires`/`assumes`, dead code or dead loop | **only** `-wp-smoke-tests` finds it → `Failed smoke-test` [v] | vacuous | Verified: `requires n > 0 && n < 0;` proves `\result == 42` for a function returning 0. The dead-code half looks innocent and bites as often — a `return 0;` after a loop that cannot exit normally is unreachable, and everything stated about it proves [v]. Mandatory gate. |
| B-6 | `axiomatic { axiom … }` | grep your own sources for `axiomatic` — WP does **no** consistency checking [doc] | unsound | One bad axiom proves everything. Prefer none; see `acsl-spec/references/logic-defs.md`. |
| B-7 | `inductive` predicate | grep sources for `inductive` [doc] | unsound | Positivity check only; still admits inconsistency that only smoke tests catch. Prefer a recursive `predicate`. |
| B-8 | Logic function declared but not defined, carrying labels | `No definition for 'f' interpreted as reads nothing` [src] | vacuous | Add a body or an explicit `reads`. Missing `reads` on pointer-dependent logic makes the spec silently vacuous [doc]. |
| B-9 | `logic int f(...)` instead of `logic integer f(...)` | grep specs for `logic +(int\|unsigned\|long)\b` | unsound | C types carry wraparound into the logic. Always `integer`/`real` in logic signatures [doc]. |
| B-10 | `admit` clause / `//@ admit lemma` | grep specs for `\badmit\b`; WP exports them as `Axiom` [src] | assumed | Every `admit` is an unproved trust anchor. Keep a register of them. |
| B-11 | Per-behavior `assigns`, no default `assigns` | `No default assigns clause, using unguarded behavior assigns` / `… using complete behaviors assigns` [src] | imprecise | Per-behavior `assigns` is poorly handled by WP [doc]. Always write one default-behavior `assigns` covering the union. |
| B-12 | `+ref` / `+caveat` memory model | `Memory model hypotheses for function 'f': …` [src] | assumed | Separation hypotheses are injected free, not proved. Add `-wp-check-memory-model` to turn them into checked clauses. |
| B-13 | `-wp-weak-int-model` | self-documented "(possibly unsound)" in `-wp-h` | unsound | Never use. |
| B-14 | `-wp-no-volatile` | fallback `ignore volatile attribute` [src] | unsound | Keep `-wp-volatile` (the default). Volatile I/O belongs in the shell. |
| B-15 | `-wp-extern-arrays` | invents a size for `extern T a[]` | assumed | Give real sizes instead. |
| B-16 | `\at(x[*p], Pre)` | **not greppable — review by hand** | wrong spec | The label distributes into *every* subterm, so `*p` is also taken at `Pre`. Bind first: `\let i = *p; \at(x[i], Pre)` [doc]. See `acsl-spec/references/memory-labels.md`. |
| B-17 | Ghost code calling a non-ghost function | Frama-C kernel rejects it [doc] | — | Ghost code calls only ghost functions. |
| B-18 | An **unproved** `lemma` used as a hypothesis by its siblings | no message; visible only when removing one lemma makes unrelated goals fail [v] | assumed | WP offers every lemma in scope as a hypothesis, discharged or not, so a false one props up its neighbours and a whole group can look proved on its strength. Track which lemmas actually discharge, and read a goal-count drop after removing one as the removal being correct. |

## 4. Tier C — supported but expensive or fragile

| # | Construct | Observed | Technique |
|---|---|---|---|
| C-1 | Linked structures with a recursive `predicate` | **all 4 goals timed out** [v], plus `Missing assigns clause` | Flat array + index handles in the verified core. If you must chase pointers: prove unfolding steps as `lemma`s rather than letting SMT unroll, raise the timeout, split into tiny functions. |
| C-2 | `(char*)int_ptr` byte access | `Cast with incompatible pointers types (source: sint32*) (target: sint8*)` + `assigns` degrades to everything + **timeout under `Typed`, `Typed+cast`, `Typed+nocast` and `Bytes` alike** [v] | Do not byte-pun in verified code. `memcpy` with a hand-written contract, or the shell. `+cast` neither silences the warning nor helps [v]. |
| C-3 | C recursion | 12/13 proved with `terminates \true; decreases n;` — the miss was a genuine overflow [v] | Always add `terminates` + `decreases`. Without it: `Missing terminates clause on call to f`. |
| C-4 | Function pointer call | without `calls`: `Missing 'calls' for default behavior` + `Unknown callee, considering non-terminating call` + assigns-everything. With `//@ calls inc, inc2;`: **16/18 proved** [v] | Put `//@ calls f1, f2;` immediately before every indirect call. [doc] says function pointers are unsupported; `calls` is the working escape hatch. |
| C-5 | Floating point | `double` + `\is_finite` **fully proved** [v] | `requires \is_finite(x)` on inputs, `ensures \is_finite(\result)`. Keep `+float`; `+real` is not C semantics. |
| C-6 | Struct by value | mostly proved [v] | Fine. For `assigns` over nested aggregates use `-wp-unfold-assigns <n>`. |
| C-7 | Missing `assigns` anywhere in the call chain | `Missing assigns clause (assigns 'everything' instead)` [v][src] | Every function including `extern` declarations and stubs needs `assigns`. Sound, but proof-killing when omitted. |
| C-8 | Loop without full annotation | missing `loop assigns` → assigns everything; missing bound invariant → RTE goals on `a[i]` fail | Every loop: `loop invariant` (bounds first, then property), `loop assigns`, `loop variant`. See `acsl-spec/references/loops.md`. |
| C-9 | Large function, many branches | `Timeout` / `Stepout` | `-wp-split`, `-wp-split-conj`, `-wp-prop`, `-wp-fct-timeout f:t`, then split the C function. |
| C-10 | Nonlinear arithmetic, wide `\forall` | `Timeout` | Helper lemmas, ghost witnesses, try z3/cvc5, then the ladder in `references/auto-active.md`. |
| C-11 | Reconstructing a pointer from its difference | goals needing `p == q + (p - q)` fail with the facts apparently all present; asserting the equality leaves the assert unproved [v] | WP does not do this rewrite. Carry a ghost index alongside the cursor so every access is a shift of the base by a known integer (`acsl-spec/references/loops.md` `## Patterns`). When the pointer comes from a call rather than a loop, state the fact in the callee instead (`acsl-spec/references/patterns.md`). |

## 5. ACSL features to avoid

Everything unimplemented is a tier A or B row above. Beyond those, the manual itself marks as
unavailable or unstable [doc]: logic type definitions, the
`\offset_min`/`\offset_max`/`\valid_range`/`\strlen` sugar, `\from` functional expressions,
volatile specification, `\allocation`, and anything labelled `\experimental` — higher-order
terms, concrete logic types, `reads`, specification modules, `allocates`/`frees`. Ghost code
is "basic support" only.

**Re-expression cheat sheet:** set → `\forall integer k` · `\lambda` → named `logic` · model
field → ghost field · `\fresh` → caller-supplied `\valid(buf + (0..n-1))` · type tag → ghost
discriminant · string literal → `static const char[]` · statement contract → extracted
function · `\inter` → explicit range.

## 6. Grep classifier

Which tier a string puts you in — that is, whether the result can be trusted. For the fix,
`references/triage.md` has the symptom index.

| Pattern | Tier |
|---|---|
| `User Error`, `Non-natural loop`, `is (potentially) recursive` | A — abort, the goal count is meaningless |
| `not implemented yet`, `not yet implemented`, `Degenerated`, `Stronger` | A/D — rewrite the annotation |
| `might be unsound` · `not yet supported (skipped)` · `Missing RTE guards` · `interpreted as reads nothing` · `using unguarded behavior assigns` · `using complete behaviors assigns` · `Memory model hypotheses for function` · `Failed smoke-test` | **B — "proved" is not evidence** |
| `Missing assigns clause` · `annot:missing-spec` · `Missing 'calls'` · `Unknown callee` · `Cast with incompatible pointers types` · `Timeout` · `Stepout` · `Unsuccess` | C — apply a technique |

That tier-B row is the list `scripts/wp.sh` greps for, and the reason it exits 3.

Two lines appear on **every** run regardless of your code and are not findings by themselves:
`Skipped RTE guards: unaligned pointers (\aligned not supported)` and
`… invalid function pointer calls (\valid_function not supported)`. They matter only if the
code actually does unaligned access or calls through a function pointer.
