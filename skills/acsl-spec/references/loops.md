# Loop annotations

Every loop gets all four clauses, ordered **bounds first, then properties**, then
`loop assigns`, then `loop variant` — which is also the order that makes triage readable.

## What each clause must satisfy

Establishment and preservation are the two people write. **Sufficiency** is the one they miss:
invariant plus negated loop condition must imply what you need after the loop. An invariant
that only bounds the index is establishable, preservable, and proves nothing about the result.

`loop assigns` lists every variable the body may change, including the induction variable.
Anything not listed is **havocked** — WP forgets its value. Omitting the clause means
"assigns everything".

A clause that lists three of four variables is as damaging as no clause at all, and harder to
spot: the loop looks annotated, and the invariant about the missing variable simply stops being
preservable. Read the body and list what it writes, including the cursor a `while (*p)` walks
and any temporary the condition assigns to. **Under-listing is the single most repeated defect
in real annotation work** — check it first when a loop will not prove.

`loop variant` proves termination only; a correct loop can still fail its variant.

## Bounds go on the closed range

The index bound is `0 <= i <= n`, not `< n` — after the final iteration `i == n`. Getting this
wrong makes preservation fail on the last step.

A backward scan is the mirror case and needs a **signed** index. A loop that walks down until
it runs off the front leaves the cursor one *before* the array, so the bound is `-1 <= e` and
`e` must be an `integer` or a signed C type. Declaring it `size_t` — the natural choice for an
index, and what `verifiable-c/references/style.md` P22 otherwise asks for — makes `e == -1`
wrap, and the invariant becomes unprovable at exactly the boundary it exists to describe.

## Patterns

**Linear search** — the invariant records what has been ruled out: `bound: 0 <= i <= n` plus
`miss: \forall integer k; 0 <= k < i ==> a[k] != v`.

**Running result** — one invariant to bound the index, one to characterise the partial result,
one witness:

```c
/*@ loop invariant bound: 0 <= i <= n;
    loop invariant upper: \forall integer k; 0 <= k < i ==> a[k] <= m;
    loop invariant wit:   i > 0 ==> \exists integer k; 0 <= k < i && a[k] == m;
    loop assigns i, m;
    loop variant n-i; */
```

Without `wit` you can prove `m` is an upper bound but not that it is one of the elements.

**In-place mutation** — add a relational invariant tying the current state back to `Pre`.
A proven bubble sort's outer loop, whose body is `for (size_type i = 1u; i < n; ++i)`:

```c
/*@ loop invariant bound:      1 <= i <= n;
    loop invariant increasing: WeaklyIncreasing(a, n-i+1, n);
    loop invariant upper:      1 < i ==> UpperBound(a, n-i+1, a[n-i+1]);
    loop invariant reorder:    MultisetReorder{Pre,Here}(a, n);
    loop assigns i, a[0..n-1];
    loop variant n-i; */
```

Two clauses are load-bearing and easy to drop when copying:

- **`reorder`** says the array is still a permutation of its entry state. Without it you prove
  the result is sorted but not that it holds the same elements — zeroing the array would
  satisfy the rest.
- **`upper`** covers index 0. At exit `i == n`, so `increasing` only gives
  `WeaklyIncreasing(a, 1, n)`; `upper` supplies `a[0] <= a[1]`. Drop it and the invariant can
  never imply the postcondition, however long the prover runs.

That second point generalises: whenever an invariant's range is offset from the array's, check
the boundary at exit.

**Pointer walk** — carry an index, not a pointer range. `os <= s <= os + n` leaves the prover
reasoning about pointer order; an exact offset gives it an equation:

```c
/*@ loop invariant idx:   s == os + k;          // ghost index, not a range
    loop invariant bound: 0 <= k <= n;
    loop invariant miss:  \forall integer i; 0 <= i < k ==> os[i] != c;
    loop assigns s, k;
    loop variant n - k; */
while (*s && *s != c) { s++; /*@ ghost k++; */ }
```

`k` is ghost state maintained alongside the pointer. It turns `os[k] == *s` into a rewrite
instead of a pointer-difference obligation, and WP will not invent it
(`frama-c-wp/references/limitations.md` C-11). The contract half of this pattern, including
what to do when the loop writes to the buffer it walks, is in `references/patterns.md`.

**Nested loops** — the inner loop must restate everything the outer invariant needs. WP does
not carry the outer invariant into the inner loop for free.

Labels available inside a loop: `Pre`, `Here`, `LoopEntry`, `LoopCurrent`
(`references/memory-labels.md`).

## Do not

- Do not use a statement-level `/*@ invariant ... */` — it is **silently dropped**
  (`Generalized invariant not yet supported (skipped)`) and the goals still "prove".
- Do not put a `goto` back-edge in a loop — WP refuses the whole function with
  `Non-natural loop detected`.
- Do not omit **or under-list** `loop assigns`. A partial list fails the same way as a
  missing one.
