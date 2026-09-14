# ACSL builtins and their WP support status

Status: **OK** verified working · **NO** rejected by WP · **avoid** experimental or
unreliable. Constructs that simply work and hold no surprise are not listed; anything absent
defaults to "check before relying on it".

## Terms and types

| Construct | Status | Note |
|---|---|---|
| `integer`, `real`, `boolean` | OK | always use these in logic signatures, never C types |
| `!e` where `e` is an integer term | OK — **and rarely what you meant** | `!` on an integer means `== 0`, so `!cmp(a,b)` asserts *equal*. Typechecks, reads as negation, silently inverts the clause. Write `cmp(a,b) != 0` |
| `\old(e)` | OK | sugar for `\at(e,Old)` |
| `\at(e,L)` | OK | **distributes into subterms** — see `references/memory-labels.md` |
| `\let x = e; ...` | OK for simple terms | complex/set bindings: `Complex let-binding not implemented yet` |
| `{ s \with .f = v }` | OK | functional update |
| `\lambda` | **NO** | `Lambda-functions not yet implemented` — verified |
| `\typeof`, `\type`, `\subtype` | **NO** | `Type tag not implemented yet` |

## Memory

| Construct | Status | Note |
|---|---|---|
| `\valid(p)`, `\valid_read(p)` | OK | ranges: `\valid(a + (0..n-1))` |
| `\separated(s1,s2,...)` | OK | the way to exclude aliasing |
| `\initialized(s)` | OK | **verified implemented** — a common myth says otherwise |
| `\base_addr`, `\block_length`, `\offset` | OK | verified |
| `\object_pointer`, `\pointer_comparable` | check | ACSL 1.19+; not exercised here |
| `\aligned(p,n)` | **NO** | `\aligned not yet implemented`; RTE guards for alignment never generated |
| `\valid_function(f)` | **NO** | `\valid_function not yet implemented`; use `//@ calls` |
| `\fresh`, `\allocable`, `\freeable`, `\dangling`, `\allocation` | **NO** | `Allocation, initialization and danglingness not yet implemented` |

## Sets and ranges

| Construct | Status | Note |
|---|---|---|
| `a[m..n]` closed range | OK | ACSL has no half-open form |
| `\union(s1,...)` | OK | works in `assigns` too — verified |
| `\subset(s1,s2)` | OK | verified; exactly 2 arguments |
| `\inter(s1,...)` | partial | **rejected inside `assigns`**: `Intersection in assigns not implemented yet` |
| set comprehension `{ f(x) \| ... }` | **NO** | `Concretization for comprehension sets not implemented yet` |
| set of pointers as a value | **NO** | `Set of pointers not yet implemented` |
| `\list<A>`, `\Nil`, `\Cons`, `\nth`, `\length` | avoid | logic lists are unreachable from lemma functions; little tool support |

## Arithmetic and maths

| Construct | Status | Note |
|---|---|---|
| `\min`, `\max`, `\abs` (integer and real) | OK | verified |
| `\sqrt`, `\pow`, `\exp`, `\log`, `\log10` | OK | verified: a true `\sqrt` lemma proves, a false one does not — the axiomatization is real, not vacuous |
| `\pi`, `\e`, trig and hyperbolic functions | OK | same axiomatization family |
| `\ceil`, `\floor`, `\atan2`, `\hypot` | OK | |
| `\round_float`, `\round_double` | check | not exercised here |
| `\sum`, `\numof`, `\product`, binder `\min`/`\max` | **NO** | need `\lambda`. Verified: `Lambda-functions not yet implemented` + `Builtin \sum(int,int,_) not defined`, goal comes back `(Stronger)`. Write a recursive `logic integer` function instead. |

## Floating point

| Construct | Status |
|---|---|
| `\is_finite`, `\is_NaN`, `\is_plus_infinity`, `\is_minus_infinity` | OK — verified, `double` + `\is_finite` proves fully |
| `\eq_float`/`\eq_double`, `\gt_`, `\ge_`, `\lt_`, `\le_`, `\ne_` | OK |

Guard every float parameter with `\is_finite` in `requires` and every float result in
`ensures`. Keep the default `+float`; `+real` is not C semantics.

## Contract clauses

| Clause | Status |
|---|---|
| `terminates`, `decreases` (incl. lexicographic) | OK |
| per-behavior `assigns` | avoid — poorly handled; put `assigns` in the default behavior |
| `check` / `admit` clause kinds | OK — but every `admit` becomes an `Axiom` |
| `allocates`, `frees` | **NO** — experimental in ACSL, unimplemented in WP |

## Statement annotations

| Construct | Status |
|---|---|
| `//@ calls f, g;` | OK — the working escape hatch for function pointers |
| `//@ ghost` statements, variables, labels | OK (basic support; cannot call non-ghost functions) |
| statement contract `/*@ requires..ensures..*/ { }` | **NO — silently dropped**, goals still "prove" |
| statement-level `/*@ invariant ... */` | **NO — silently dropped** |

## Logic declarations

| Construct | Status |
|---|---|
| `logic <type> f(...) = ...;` incl. recursive and overloaded | OK — the house style |
| `predicate P{L}(...) = ...;` incl. two-state `{K,L}` | OK — the house style |
| `lemma Name: ...;` incl. `lemma Name{K,L}:` | OK — the house style |
| `axiomatic { ... }` | works, but **no consistency checking** — avoid |
| `inductive` | works, positivity check only — avoid |
| `reads` clause | experimental; **mandatory** if you declare pointer-dependent logic without a body |
| concrete logic types (record/sum) | experimental — avoid |
| specification modules | experimental — avoid |
| `model` variables and fields | **NO** — `Model field` not implemented |
| `global invariant` / `type invariant` | avoid — model invariants as ordinary predicates |
