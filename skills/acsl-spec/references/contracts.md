# Function contracts

The skeleton is in `assets/contract.h` and in the `acsl-spec` skill body. This file is the
part that is not obvious: what omission means, what WP enforces, and where `assigns` bites.

## Clause order

`requires` · `terminates` · `exits` · `decreases` · `assigns` · `ensures` · `behavior`s ·
`complete`/`disjoint`.

Part of that is **enforced, not conventional**: `terminates` and `decreases` must precede any
post-condition, `assigns` or `allocates`. Putting `assigns` first is a fatal parse error —
verified: `wrong order of clause in contract: terminates after post-condition, assigns or
allocates.` The rest is free, so `terminates \true; assigns \nothing; exits \false;` parses
as well as the order above. Pick one and keep it.

Contract on the **prototype in the header**, loop annotations in the `.c`. That is how WP
reads it modularly across a call boundary.

## What omission means

Omitting a clause is not a neutral act.

| Clause | If you omit it |
|---|---|
| `assigns` | **everything may change.** Not `\nothing`. Callers learn nothing, and every caller goal after the call fails. |
| `terminates` | callers get `Missing terminates clause on call to f` |
| `exits` | the function is assumed able to `exit()`; write `exits \false;` for ordinary functions |
| `decreases` on a recursive function | `Missing decreases clause on recursive function f` — recursion cannot be proved |
| `requires` | the function must work for *every* input, including null pointers and extreme values |

## Naming every clause

`requires valid:`, `ensures sorted:`, `loop invariant bound:`. A **functional requirement**,
not style: `-wp-prop=bound` is how you re-run one goal out of a hundred during triage, and an
unnamed clause cannot be isolated.

Reuse one label vocabulary project-wide so `-wp-prop` targets predictably: `valid`, `sep`,
`bound`, `result`, `upper`, `lower`, `increasing`, `reorder`, `max`, `capacity`, `storage`,
`equal`, `unchanged`.

## assigns

The forms are **alternatives**, not lines to combine:

```c
assigns \nothing;              // pure function - excludes every other assigns clause
assigns a[0..n-1];             // a slice - ACSL has no half-open form
assigns s->data \from data;    // with a dependency
assigns \result \from a[0..n-1];
```

- **`\nothing` cannot be mixed with a real location.** `assigns \nothing; assigns \result
  \from s;` is rejected: "Mixing \nothing and a real location". For a pure function computing
  a result from its inputs, `assigns \result \from s;` alone is the whole clause; `\nothing`
  is for a function whose result depends on nothing.
- `assigns` tracks **values that may change**, not memory touched. A loop doing `a[i] = a[i];`
  is legitimately `assigns \nothing;`.
- `\union` works in `assigns`. `\inter` does not — write the explicit range.
- Put `assigns` in the **default behavior**. Per-behavior `assigns` is poorly handled by WP
  and triggers `No default assigns clause, using unguarded behavior assigns`. Repeat it inside
  a behavior only as a refinement, never as the only occurrence.
- `extern` declarations and library stubs need `assigns` too, or every call to them destroys
  the caller's knowledge.

## Behaviors

- `assumes` must constrain the **pre-state** only.
- Behaviour-independent facts go in the top-level `ensures`, before the split.
- Close with `complete behaviors; disjoint behaviors;` whenever the cases are exhaustive and
  mutually exclusive — both become proof obligations that catch a mis-split.

## Termination and recursion

```c
terminates n >= 0;      // conditional; \true for an ordinary function
decreases  n;           // recursive: integer measure, >= 0, strictly decreasing
decreases  n, k;        // lexicographic
```

Recursion works given both — verified, 12/13 goals on a factorial, the miss being a genuine
overflow. Recursion on the entry point does not work at all; use a non-recursive wrapper.

## Calls through function pointers

```c
//@ calls inc, inc2;
r = f(x);
```

Without it WP assumes the callee may be anything, including this function, and `assigns`
collapses. With it, 16/18 goals proved. `\valid_function` is **not** implemented, so "is this
a real function pointer" is never checked — record that as an assumption.

## Integer bounds

With `-wp-rte` and the two unsigned checks on by default, arithmetic generates goals. State
the bounds you rely on, or they become unprovable obligations:

```c
requires n <= SIZE_TYPE_MAX - 1;      // so i++ cannot wrap
```

Logic signatures always use ACSL `integer`/`real`, never C `int` — `logic int f(...)` carries
C wraparound into the logic and is silently unsound.
