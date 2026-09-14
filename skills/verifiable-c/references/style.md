# C style for provability

**H** = hard requirement: violate it and WP cannot verify the code, or the result cannot be
trusted. **P** = strong preference: violate it and the proof gets slow, brittle or ten times
more annotation.

Each rule states what breaks, with the exact symptom where one was observed.

## Architecture

- **H1 — Split a verified core from an unverified shell.** The core is pure computation over
  caller-supplied memory. The shell owns `malloc`/`free`, I/O, `volatile` MMIO, byte punning,
  `setjmp`, threads. Every hard blocker below is a shell concern.
  *Breaks:* `Allocation, initialization and danglingness not yet implemented` — the core
  becomes unprovable in principle.
- **H2 — Every callee reachable from a verified function has a contract**, `extern`
  declarations and library stubs included. Minimum `assigns` and `terminates`.
  *Breaks:* `Missing assigns clause (assigns 'everything' instead)`, then cascading timeouts.
- **P3 — Functions ≤ ~50 lines, one loop, ≤ ~4 branches.** VC size grows with path count.
  *Breaks:* `Timeout`/`Stepout`, and `-wp-split` stops helping.
- **P4 — Contract in the header, body and loop annotations in the `.c`.** Mirrors WP's modular
  reading. *Breaks:* `annot:missing-spec <header>:<line>`, and a callee whose postcondition
  looks unusable rather than absent — `references/project-layout.md`.
- **P5 — Shared predicates in guarded `.acsl` headers.** Caller and callee then see
  syntactically identical terms, which is what the solver matches on.

## Data shape

- **H6 — Array parameters are `T *a, size_type n`**, never sentinel-terminated or unsized.
  *Breaks:* `Validity of unsized-array not implemented yet`; `\valid` of `extern T a[]` is
  unprovable.
- **H7 — No pointer casts in verified code.** No `(char*)`, no `void*` round-trips, no punning.
  *Breaks:* `Cast with incompatible pointers types (source: sint32*) (target: sint8*)`, then
  `assigns` degrades to everything, then everything times out. Verified: this times out under
  `Typed`, `Typed+cast`, `Typed+nocast` **and** `Bytes` alike, and `+cast` does not even
  silence the warning.
- **H8 — No unions in verified code.** Use a tagged struct. *Breaks:* `Accessing union fields
  with Typed model might be unsound.` — and **goals still report proved**. The most dangerous
  silent failure there is.
- **P9 — Prefer flat arrays with index handles over pointer-linked structures.** *Breaks:* a
  linked list with a recursive `valid_list` predicate timed out on all four goals. Model a
  stack as `{data, size, capacity}` over a flat array, never as a chain.
- **P10 — Struct by value for small immutable aggregates; pointer plus `\valid` for anything
  mutated.** By-value structs are pure logic values and prove well. Nested aggregate `assigns`
  may need `-wp-unfold-assigns <n>`.
- **P11 — Minimise globals; give every unavoidable one an explicit `assigns`.** A `static`
  counter with `assigns counter;` proves fully. Omit it and the caller concludes nothing.

## Control flow

- **H12 — Natural loops only: `for`, `while`, `do-while`. Never a `goto` back-edge.**
  *Breaks:* `Non-natural loop detected in function 'f'. This case is not supported yet (skipped
  verification).` — a **User Error that aborts WP for the whole function**, and therefore the
  first thing to fix on existing code.
- **P13 — Forward `goto` to a single cleanup label is fine**; the CFG stays reducible. Two
  interleaved cleanup labels can still form an irreducible region.
- **P14 — Early `return` is fine.** WP handles multiple exits natively, including returns from
  inside loops. Single-exit discipline is a MISRA habit, not a WP requirement, and usually
  costs an extra flag variable and an extra invariant.
- **H15 — Every loop carries `loop invariant` (bounds, then properties), `loop assigns`,
  `loop variant`.** *Breaks:* missing `loop assigns` means assigns-everything; a missing bound
  invariant makes the RTE goal on `a[i]` fail.
- **H16 — No statement contracts.** Extract the block into a function. *Breaks:* `Statement
  specifications not yet supported (skipped).` — silently dropped, goals still "prove".
- **H17 — No indirect call without `//@ calls f, g;` at the call site.** *Breaks:* `Missing
  'calls' for default behavior` + `Unknown callee, considering non-terminating call` +
  assigns-everything. With `calls`, 16/18 goals proved.
- **H18 — Recursive functions carry `terminates \true; decreases <measure>;`.** Recursion on the
  entry point does not work at all — use a non-recursive wrapper.

## Integers and arithmetic

- **H19 — Verify with `-wp-rte`, and with `-warn-unsigned-overflow -warn-unsigned-downcast`
  on by default.** *Breaks:* `Missing RTE guards` and a 100% score that means nothing. The one
  supported exception, and what such a run owes the reader, is in `references/hostile-c.md`.
  Never drop a check to turn a run green.
- **H20 — Logic signatures use ACSL `integer`/`real`, never C `int`.** *Breaks:* silently
  unsound lemmas, with no message at all.
- **P21 — One `value_type`/`size_type` typedef pair project-wide**, with matching `*_MAX`
  macros. One set of bound lemmas becomes reusable; mixed `int`/`size_t`/`unsigned` explodes
  into downcast goals. Starting point: `acsl-spec/assets/typedefs.h`.
- **P22 — Unsigned for lengths and indices, with the bound stated**: `requires n <=
  SIZE_TYPE_MAX - 1;`. *Exception:* an index that can go one position past an end — a backward
  scan running off the front — must be signed, bound written `-1 <= e`. Made unsigned it wraps
  at exactly the boundary the invariant exists to describe
  (`acsl-spec/references/loops.md` `## Bounds go on the closed range`).
- **P23 — Never mix signed and unsigned in one expression; no implicit narrowing.**
- **P24 — Floats: `requires \is_finite(x)` on inputs, `ensures \is_finite(\result)` on outputs;
  keep the default `+float`, never `+real`.** Verified: `double` with `\is_finite` proves fully.

## Aliasing and framing

- **H25 — State `\separated` for every pair of pointer ranges that must not overlap.**
  *Breaks:* a postcondition about `a` fails after writing `b`, correctly.
- **P26 — `const` on every read-only pointer parameter.** Justifies `\valid_read` and keeps
  the parameter out of `assigns`.
- **P27 — Prefer `\separated` over `restrict`.** WP does not consume `restrict` as a contract.
- **H28 — `assigns` on every function and every loop, in the default behavior.** *Breaks:* `No
  default assigns clause, using unguarded behavior assigns`.
- **P29 — Pure functions declare `assigns \nothing;`** — the strongest frame, and it makes
  callers trivial.
- **P30 — Stay on the default `-wp-model Typed`.** `+ref`/`+caveat` inject unproved
  separation hypotheses; if you must, add `-wp-check-memory-model`. `Bytes`/`Region`/`Eva`
  are experimental and slow.

## Specification hygiene

- **H31 — No `axiomatic` blocks, no `inductive` predicates.** Recursive `logic`/`predicate`
  plus `lemma` instead: WP does zero consistency checking on axioms.
- **H32 — Run `-wp-smoke-tests` before declaring anything proved.** The only detector of
  vacuous contracts. Verified: `requires n > 0 && n < 0;` proves `\result == 42` for a
  function that returns 0.
- **P33 — Name every clause.** Enables `-wp-prop` targeting, which is how triage works.
- **P34 — `\at(...)` wraps a single simple term**; bind indices with `\let` first.
- **P35 — Prefer `lemma` plus explicit instantiation over deep recursive logic functions.**

## Refactoring order for existing code

1. **H12** kill irreducible loops — nothing else runs until this is done
2. **H1** carve out the unverified shell
3. **H6/H7/H8** fix the data shape
4. **H2** contracts on all callees
5. **H28** `assigns` everywhere
6. **H15** loop annotations
7. **H19/H32** turn on RTE and smoke tests
8. functional postconditions last
