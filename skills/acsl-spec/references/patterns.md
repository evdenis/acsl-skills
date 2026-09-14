# Specification patterns

Reusable idioms, all verified in practice. The array section assumes one project-wide
`value_type`/`size_type` pair (`assets/typedefs.h`). The pointer-walking section covers string
and buffer code, which is array-free and hits a different set of obstacles.

## Array range predicates

The set worth defining once, over a range `[m, n)`, each overloaded down to an `(a, n, ...)`
form defaulting `m = 0`: `Unchanged{K,L}`, `Equal{K,L}`, `LowerBound`/`UpperBound` and their
strict variants, `MaxElement`, `Partition`. The two-state ones are the shape that matters:

```c
predicate Unchanged{K,L}(value_type* a, integer m, integer n) =
  \forall integer i; m <= i < n ==> \at(a[i],K) == \at(a[i],L);

predicate MaxElement{L}(value_type* a, integer n, integer max) =
  0 <= max < n && UpperBound(a, n, a[max]);
```

Keep one definition per fact, so caller and callee match syntactically.

## Pointer-walking code, specified over indices

String and buffer code walks a cursor instead of indexing an array, and the natural
specification — quantify over pointers, bound the cursor with a range — does not survive
contact with the Typed model, which reasons in base and offset. Four rules cover most of it.

**Quantify over `integer`, never over pointers.** A contract ranging over `char *` gives the
solver goals that reduce to pointer-order contradictions — in one measured case literally
`a < s && s <= a ==> ...`, unprovable because it is contradictory, not because it is hard.
Index from the base instead:

```c
requires \valid_read(s + (0..n-1));
ensures  \forall integer i; 0 <= i < n ==> s[i] != c;
```

**Characterise a returned pointer by its offset.** `0 <= \result - s <= strlen(s)` says
everything `\base_addr(\result) == \base_addr(s)` said and more, so the `\base_addr` clause
goes. The loop half — a ghost index giving the cursor a known offset — is in
`references/loops.md` `## Patterns`; why you must carry it is
`frama-c-wp/references/limitations.md` C-11.

**When the function writes to the buffer it reads, phrase the contract over `Pre`.** This
decides whether such a function is provable at all. The obstacle in a copy or in-place edit is
not that WP cannot show the source survives the write — it is that a post-state contract
*asks* for that. Say what was true on entry, and carry a pointwise invariant that the
untouched part still holds its entry value:

```c
/*@ requires \separated(dest + (0..n), src + (0..n));
    assigns  dest[0..n];
    ensures  \forall integer i; 0 <= i <= n ==> dest[i] == \at(src[i], Pre);
    ensures  \result == strlen{Pre}(src);
 */
```

Alongside the `idx`/`bound` pair from `references/loops.md`, the loop carries the two that make the
postcondition reachable:

```c
loop invariant untouched: \forall integer i; 0 <= i <= n ==> osrc[i] == \at(src[i], Pre);
loop invariant copied:    \forall integer i; 0 <= i <  k ==> odest[i] == \at(src[i], Pre);
```

`untouched` follows from `\separated` directly — a pointwise frame fact, so nothing has to be
re-derived about a recursive `strlen`. Eight string functions that looked like they needed a
two-label frame lemma were closed this way, with no Coq. Write `\at(src[i], Pre)` on the
formal, not on the ghost copy: a ghost variable does not exist at `Pre`
(`references/memory-labels.md`). These two clauses are the `Unchanged`/`Equal` shapes above,
indexed from the base.

**State a fact about a returned pointer in the callee.** A caller receiving a pointer holds
only its difference from the base and WP will not rebuild the pointer. Inside the callee the
ghost index still exists, so the fact is immediate there:

```c
// in skip_spaces, whose body carries `\result == os + k`
ensures \result == str + (\result - str);
// in strpbrk, whose caller needs to write through the result
ensures \valid(\result);
```

The same move gives a comparison function a postcondition carrying the witness index: it
proves inside the callee, where the witness is known, and is unstatable anywhere else.

## Sortedness

`WeaklyIncreasing{L}(a, m, n)` is `\forall integer i; m <= i < n-1 ==> a[i] <= a[i+1]`, and
`Increasing` is the strict version. State the transitive and shift lemmas once alongside the
predicate; every proof over a sorted range needs them.

## Permutation, without a primitive

ACSL has no permutation predicate, and inventing one as an `axiomatic` is the wrong move.
Define permutation **extensionally, through occurrence counts**:

```c
logic integer Count(value_type* a, integer m, integer n, value_type v) =
  n <= m ? 0 : Count(a, m, n-1, v) + (a[n-1] == v ? 1 : 0);

predicate MultisetReorder{K,L}(value_type* a, integer m, integer n) =
  \forall value_type v; Count{K}(a, m, n, v) == Count{L}(a, m, n, v);
```

"The range holds the same multiset of values in state `K` as in state `L`." This is the
relational invariant every in-place sorting proof needs:

```c
loop invariant reorder: MultisetReorder{Pre,Here}(a, n);
```

Layered on top, each with its own lemma set:

| Predicate | Meaning |
|---|---|
| `ArraySwap{K,L}(a,i,k,n)` | values at `i` and `k` traded, rest unchanged |
| `MultisetSwap` lemmas | `ArraySwap` implies `MultisetReorder` |
| `ArrayUpdate{K,L}(a,n,i,v)` | one index overwritten |
| `MultisetAdd`/`Minus`/`RetainRest` | count deltas of +1 / -1 / 0 |
| `MultisetParity{K,L}(a,n,u,v)` | one value `u` replaced by `v` |

Use `ArraySwap`-based lemmas for algorithms that exchange pairs (bubble, selection), and
`MultisetParity` for those that move one value at a time (heap sift).

## Contract for an in-place mutator

The read-only shape is in the `acsl-spec` skill body. The mutator is the one with a trap:

```c
/*@
  requires   valid: \valid(a + (0..n-1));
  terminates \true;
  exits      \false;
  assigns    a[0..n-1];
  ensures    sorted:  WeaklyIncreasing(a, n);
  ensures    reorder: MultisetReorder{Pre,Here}(a, n);
*/
void bubble_sort(value_type* a, size_type n);
```

Both are needed. Sortedness alone is satisfied by a function that zeroes the array.

## The assigns lesson

A loop doing `a[i] = a[i];` proves under `assigns \nothing;` and equally under
`assigns a[0..n-1];`. `assigns` constrains **values that may change**, not memory that is
written.

## Modelling state as a struct

For a stack, queue or buffer, model the invariant as an ordinary predicate over a flat array,
not with ACSL's `type invariant`, which WP handles poorly:

```c
predicate StackInvariant{L}(Stack* s) =
  \valid(s) && 0 <= s->size <= s->capacity && \valid(s->data + (0..s->capacity-1));
```

Pass it as a `requires` and re-establish it in every `ensures`. Split the definitions across
`.acsl` headers by role — the invariant, the observers, the separation facts — so a proof
pulls in only what it needs.

## Composition instead of re-verification

A predicate-over-range function such as `all_of`/`any_of`/`none_of` needs a single
postcondition and **no loop annotations at all** if it delegates to an already-verified `find`
and inspects the returned index. Reuse a proved function rather than re-proving its loop.
