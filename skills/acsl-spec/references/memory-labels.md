# Memory, validity and labels

## Validity and separation

`\valid_read` for `const T *`, `\valid` for anything you write. `\valid` on a read-only
parameter is not wrong, just a stronger precondition than you need, pushing work onto callers.
`\initialized` **is** implemented and usable, contrary to a common belief.

`n == 0` makes `a + (0..n-1)` the empty set, which is trivially valid. That is usually what you
want; if the pointer must be valid even for an empty range, say so separately.

Two pointer parameters may alias unless you rule it out, so any function that writes through
one and reads through another needs
`requires sep: \separated(dst + (0..n-1), src + (0..n-1));`. Without it a postcondition about
`src` fails after writing `dst`, and correctly so. `restrict` is a compiler hint that WP does
not consume as a contract — use `\separated`.

## Labels

`Pre` · `Post` · `Old` (in an `ensures`, same as `Pre`; `\old(e)` is sugar for `\at(e,Old)`) ·
`Here` · `LoopEntry` · `LoopCurrent` · `Init` (after global initialisation).

Two-state predicates take labels as parameters, written `{K,L}` with `K` the earlier state:

```c
predicate Unchanged{K,L}(value_type* a, integer m, integer n) =
  \forall integer i; m <= i < n ==> \at(a[i],K) == \at(a[i],L);
```

## The `\at` footgun

**`\at` distributes into every subterm.**

```c
\at(x[*p], Pre)     // means  \at(x[\at(*p,Pre)], Pre)  -- NOT  \at(x,Pre)[*p]
```

If `*p` changed during the function this is a different property from the one you meant, and
it will prove or fail for reasons that make no sense. Bind the index first:

```c
\let i = *p; \at(x[i], Pre)
```

Not detectable by grepping WP's output. Review every `\at` by hand whenever the term inside it
contains a dereference or an index the function modifies.

## Ghost labels and snapshots

Declare a label ACSL's built-ins cannot reach with an empty ghost statement, and keep a
pre-mutation value with a ghost variable:

```c
//@ ghost Before: ;
//@ ghost value_type ac = a[c];
... code that overwrites a[c] ...
//@ assert update:  ac == \at(a[c], Epilogue);
//@ assert reorder: MultisetParity{Before,Here}(a, n, ac, v);
```

**A ghost variable cannot be read at a label that predates it.** `\at(ac, Pre)` does not
typecheck: `ac` does not exist at `Pre`. This bites when a loop keeps a ghost copy of a
parameter — write `\at(a[c], Pre)` on the formal, which does exist there.

## Ghost code rules

It cannot alter control flow, normal code cannot read ghost memory, ghost code cannot write
normal memory, **it cannot call non-ghost functions**, and **it cannot call a logic function
or branch on a predicate** — ghost code is C, so a condition has to be C-expressible. Lift the
predicate into a helper ghost function returning an `int` and branch on that; replace a
`ghost size_t n = strlen(s);` binding with the logic term `strlen{Pre}(s)` in the annotation
that needs it. You remain responsible for its termination and RTE-freedom — non-terminating
ghost code can prove `\false`.

## Not implemented — do not use

`\aligned`, `\valid_function`, `\fresh`, `\allocable`, `\freeable`, `\dangling`, `\allocation`.
See `frama-c-wp/references/limitations.md` A-12 to A-14. WP also never generates RTE guards
for pointer alignment or function-pointer validity, on any run.
