---
name: acsl-spec
description: Write, repair or strengthen ACSL annotations on C code — function contracts (requires, assigns, ensures, terminates, exits, behaviors), loop invariants and variants, predicates, logic functions, lemmas, ghost code, and \at/labels. Use when asked to specify or annotate existing C, add contracts to a function or header, or fix a wrong, weak or incomplete invariant, postcondition or assigns clause. Does not run the prover — pair with the frama-c-wp skill for that.
license: MIT
---

# Writing ACSL specifications

**Requires** Frama-C 33 with the WP plugin to check the annotations; the `frama-c-wp` skill
runs it.

## Order of work

1. **Read what the function actually does**, edge cases included: `n == 0`, null pointer,
   overflow at the extremes.
2. **Frame first** — `requires` for validity and separation, then `assigns`, then
   `terminates`/`exits`. A wrong frame makes every functional goal fail for the wrong reason.
3. **Then the functional postcondition**, then loop annotations, bounds before properties.
4. **Then prove it**, through the `frama-c-wp` skill. A specification that has never been run
   is not a specification.

## The complete contract

```c
/*@
  requires   valid: \valid_read(a + (0..n-1));
  // only when a second buffer exists; `b`/`m` must be real parameters, else
  // Frama-C rejects the whole contract with "unbound logic variable b"
  // requires sep: \separated(a + (0..n-1), b + (0..m-1));

  terminates \true;
  exits      \false;
  assigns    \nothing;

  ensures    result: 0 <= \result <= n;

  behavior some:
    assumes  \exists integer i; 0 <= i < n && a[i] == v;
    ensures  hit: a[\result] == v;
  behavior none:
    assumes  \forall integer i; 0 <= i < n ==> a[i] != v;
    ensures  miss: \result == n;
  complete behaviors;
  disjoint behaviors;
*/
size_type find(const value_type* a, size_type n, value_type v);
```

Contract on the prototype in the `.h`; loop annotations in the `.c`.

## The loop

```c
/*@
  loop invariant bound: 0 <= i <= n;
  loop invariant miss:  \forall integer k; 0 <= k < i ==> a[k] != v;
  loop assigns i;
  loop variant n-i;
*/
```

Establishment and preservation are the easy two. The one usually missing is **sufficiency**:
invariant plus negated loop condition must imply the postcondition. An invariant that only
bounds the index proves nothing about the result.

In-place mutation also needs a relational invariant back to `Pre`
(`loop invariant reorder: MultisetReorder{Pre,Here}(a, n);`), or you prove the array is sorted
without proving it still holds the same elements.

## House rules

- **Name every clause.** `requires valid:`, `loop invariant bound:`. This is functional, not
  cosmetic — `-wp-prop=bound` is how a single goal gets isolated during triage.
- **Always write `assigns`.** Omitting it means *everything may change*, not nothing. This
  applies to `extern` declarations and stubs too.
- **`assigns` goes in the default behavior.** Per-behavior `assigns` is poorly handled by WP.
- **Always write `terminates` and `exits`.** `terminates \true; exits \false;` for an ordinary
  function.
- **Logic signatures use `integer`/`real`, never C `int`.** A `logic int f(...)` drags C
  wraparound into the logic and is silently unsound.
- **No `axiomatic` blocks, no `inductive` predicates.** WP does no consistency checking on
  axioms; one bad axiom proves everything. Use recursive `logic`/`predicate` plus named
  `lemma`s.
- **Ranges are closed**: `a[0..n-1]`. ACSL has no half-open form.
- **Shared definitions go in a guarded `.acsl` header**, included from annotations. This needs
  `-pp-annot` or the include silently does nothing.

## Traps

Each of these typechecks, reads as if it means something else, and no grep will find it.

- **`\at` distributes into subterms.** `\at(x[*p], Pre)` also takes `*p` at `Pre`. Bind first:
  `\let i = *p; \at(x[i], Pre)`. Review by hand.
- **Statement contracts are silently dropped.** `/*@ requires..ensures..*/ { ... }` emits
  `Statement specifications not yet supported (skipped)` and the function still reports every
  goal proved. Extract the block into a real function instead.
- **Statement-level `/*@ invariant ... */` is silently dropped** too. Use `loop invariant`.
- **A contradictory `requires` proves everything.** `requires n > 0 && n < 0;` will prove any
  postcondition you write. Only `-wp-smoke-tests` catches it.
- **`!` on an integer term means `== 0`.** `ensures !cmp(a, b);` asserts the comparison is
  *equal*, which is the opposite of how it reads. Verified: `!cmp(3,5)` fails, `!cmp(5,5)`
  proves. Write `cmp(a, b) != 0`.
- **A recursive `logic` definition that does not descend makes everything provable.**
  `f(s) = ... : 1 + f(s)` asserts `0 == 1`; the goals then prove vacuously and the score is
  meaningless. See `references/logic-defs.md`.

Before using an unfamiliar builtin, check `references/builtins.md` — `\lambda` and therefore
`\sum`/`\numof`/`\product` are rejected, and `\fresh`, `\aligned`, `\valid_function` and model
fields are unimplemented.

## Fixing an existing specification

A failing goal is a weak specification far more often than a slow prover. Dump the goal and
read `Assume` (what WP believes) against `Prove` (the obligation):

```sh
../frama-c-wp/scripts/wp-goal.sh -f myfunc -p clause-name -r file.c
```

Relative to this skill's directory, which is normally not your shell's working directory:
resolve it to an absolute path first (in Claude Code, `${CLAUDE_SKILL_DIR}` expands to it).

A fact missing from `Assume` means the `requires`, `loop invariant` or callee `ensures` that
should have supplied it is too weak. Strengthen that — never weaken the postcondition to make
it pass, which deletes the property instead of proving it.

## Closing the loop

Annotating is not finishing. Return to the `acsl-verify` skill, which owns the run/triage loop
and the done criteria; stopping at `wp.sh` exit 0 is not done.

## Reference

| Need | Read |
|---|---|
| writing or debugging a clause: semantics, behaviors, `assigns` | `references/contracts.md` |
| a loop will not prove, or you are writing one | `references/loops.md` |
| defining a predicate, logic function or lemma | `references/logic-defs.md` |
| `\valid`, `\separated`, `\at`, labels, ghost code | `references/memory-labels.md` |
| array, sortedness, permutation or pointer-walking idioms | `references/patterns.md` |
| is this builtin supported? | `references/builtins.md` |
| what WP cannot verify at all | `frama-c-wp/references/limitations.md` |
| starting points | `assets/contract.h`, `assets/loop.c`, `assets/logic.acsl`, `assets/typedefs.h` |
