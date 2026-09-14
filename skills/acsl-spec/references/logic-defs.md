# Logic definitions: predicates, logic functions, lemmas

## House style

Use plain recursive `logic` functions and `predicate`s, plus named `lemma`s.
**Do not use `axiomatic` blocks. Do not use `inductive` predicates.**

This is soundness, not taste: WP performs no consistency checking on axioms at all, and one
bad axiom proves everything. `inductive` gets a positivity check that still admits
inconsistency. Large verified codebases are built entirely from recursive definitions plus
named lemmas, with zero of either construct.

Much introductory Frama-C material teaches `axiomatic` and `inductive`. Treat that as
background, not as the style to emit.

## Shape of a logic header

Shared definitions live in a guarded `.acsl` file, included like a C header. This needs
`-pp-annot` on the command line or the include silently does nothing.

```c
#ifndef COUNT_ACSL_INCLUDED
#define COUNT_ACSL_INCLUDED

#include "Equal.acsl"

/*@
  logic integer
  Count(value_type* a, integer m, integer n, value_type v) =
    n <= m ? 0 : Count(a, m, n-1, v) + (a[n-1] == v ? 1 : 0);

  logic integer
  Count(value_type* a, integer n, value_type v) = Count(a, 0, n, v);

  lemma Count_Empty:
    \forall value_type *a, v, integer m, n;
      n <= m  ==>  Count(a, m, n, v) == 0;

  lemma Count_Union:
    \forall value_type *a, v, integer k, m, n;
      0 <= k <= m <= n  ==>
      Count(a, k, n, v) == Count(a, k, m, v) + Count(a, m, n, v);
*/

#endif /* COUNT_ACSL_INCLUDED */
```

Conventions visible here and worth copying:

- **`PascalCase`** for predicates and logic functions.
- **Overloads** from a general `(a, m, n, ...)` form down to `(a, n, ...)` defaulting `m = 0`.
- **`Predicate_Property`** lemma names (`Count_Union`, `MultisetReorder_DisjointUnion`). This
  maps one-to-one onto Coq filenames later, which matters if you end up there.
- **Two-state predicates** written `Name{K,L}` with `K` the earlier state.
- Logic signatures use ACSL `integer`/`real`, **never** C `int` — a `logic int f(...)` carries
  wraparound into the logic and is silently unsound.

Two things about a recursive definition are load-bearing, and neither produces a diagnostic
when you get it wrong.

**The recursive call must descend.** `Count(a, m, n-1, v)` advances; a definition whose call
does not — `f(s) = ... : 1 + f(s)` where `f(s + 1)` was meant — asserts `f(s) == 1 + f(s)`,
i.e. `0 == 1`. It typechecks. Everything stated in terms of it then proves vacuously, and WP
will discharge `assert \false` from it given a witness. Measured on one such file: 335/346
goals "proved", 311/346 once the recursion was fixed — 24 goals had been resting on the
contradiction. Audit every recursive definition in the file at once when you find one.

**The step is load-bearing.** `Count(a, m, n-1, v) + (a[n-1] == v ? 1 : 0)` counts; drop the
increment from a definition that is supposed to return an *index* and it typechecks cleanly
and can only ever return 0 — which makes every contract written in its terms assert exactly
that, about a function that does no such thing.

## Lemmas are the main tool

A recursive logic function is expensive for SMT: solvers unroll it and time out on anything
non-trivial. State the algebraic facts you need as `lemma`s once, prove each on its own, and
let the solver use them as rewrite rules.

Typical lemma set for a recursive range function: `_Empty` (base case), `_Hit`/`_Miss` (one
step), `_Union` (split a range), `_Cut` (split off one element), `_Shift` (re-index),
`_Unchanged{K,L}` (stable across a state change), `_Equal{K,L}` (agrees on equal ranges).

Front-loading that set is what keeps hand-written Coq proofs rare.

The same mechanism is a hazard: WP offers every lemma in scope as a hypothesis, **including
ones it never discharged**, so a false lemma props up its neighbours. Track which lemmas
actually prove, and read unrelated goals failing after you remove a bad one as the removal
being correct (`frama-c-wp/references/limitations.md` B-18).

## When a lemma will not prove

Lemmas about recursive definitions need induction, which SMT does not do. Encode it as a
**lemma function** in C (`frama-c-wp/references/auto-active.md`); fall back to the `wp-coq`
skill only if that cannot express it. Full ladder: `frama-c-wp/references/triage.md`.

## If you must use `axiomatic`

Only when what you need genuinely cannot be defined constructively. Then:

- Every axiom is an unproved assumption. Record it.
- Add an explicit `reads` clause to any pointer-dependent declaration. Without it, the
  definition silently reads nothing and your specification becomes vacuous
  (`No definition for 'f' interpreted as reads nothing`).
- Run `-wp-smoke-tests`. It is the only thing that will catch an inconsistent axiom set.
- Never declare a logic function with a C integer type.
- An ill-founded recursion inside an `axiomatic` is the worst case of all: the block becomes
  inconsistent and everything in scope proves. The descent check under
  `## Shape of a logic header` applies here too.

## Quantifiers

Quantify over **bounded `integer` indices, never over pointers**, even when the code walks a
cursor: the Typed model reasons in base and offset, and a clause ranging over `char *` yields
pointer-order goals that reduce to contradictions. See `references/patterns.md`
`## Pointer-walking code, specified over indices`.

Sets are not an alternative — set-of-pointers and set-comprehension terms are unimplemented
(`frama-c-wp/references/limitations.md` A-9, A-10).

## Not implemented — avoid

`\lambda` and the higher-order aggregators (`\sum`, `\numof`, `\product`, `\min`, `\max` in
binder form) are marked experimental in the manual and `\lambda` is rejected outright by WP.
Concrete logic types (records, sums) and specification modules are experimental too. Use named
logic functions instead.
