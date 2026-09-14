# Coq proof recipes for WP goals

The job is mostly `rewrite` with lemmas you already proved, plus `lia` for the arithmetic;
`auto with zarith`, `intros`, `replace`, `assert`, `apply`, `unfold`, `destruct`,
`natlike_rec2` and `remember` cover nearly all the rest. Genuine induction is rarer than it
looks.

## Preamble inside the proof

Put the imports **inside** the `Proof.` block — outside it they are destroyed by
`-wp-interactive update`:

```coq
Proof.
  Require Import Psatz.       (* lia *)
  Require Import ZArith.
  intros K L a m n L32 K32.
  ...
Qed.
```

## Induction over a non-negative integer

This is the workhorse. `natlike_rec2` gives you base case and step:

```coq
apply natlike_rec2 with (z := n); auto with zarith.
- (* base: n = 0 *)
  rewrite Q_Count_Empty; auto with zarith.
- (* step *)
  intros z Hz IHz.
  replace (Z.succ z) with (1 + z)%Z by lia.
  rewrite <- Q_Count_Hit by lia.
  lia.
```

When the range is `[m, n)` rather than `[0, n)`, re-base first:

```coq
remember (n - m)%Z as p.
replace n with (m + p)%Z in * by lia.
assert (pNN: (0 <= p)%Z) by lia.
apply natlike_rec2 with (z := p); auto with zarith.
```

## Using the lemmas you already stated

Every ACSL `lemma` in scope is available as `Q_<name>`. This is what keeps the proofs short:

```coq
rewrite <- Q_Count_Union with (m := k); auto with zarith.
rewrite Q_Count_Empty; auto with zarith.
apply Q_Unchanged_Shrink with (n := (1 + z)%Z); auto with zarith.
```

If a step feels hard, the right move is usually to **add another ACSL lemma** and prove it
separately, not to push harder in Coq.

## Unfolding a predicate

```coq
unfold P_MultisetReorder_1_. intros v V32.
```

Two-state predicates unfold to a `\forall` over values; `intros` the quantified variable and
its range hypothesis.

## Case split

```coq
assert (X: (i < z \/ i = z)%Z) by lia.
destruct X as [less | equal].
```

## The printing gotchas

**`-1` prints as `- (1)`.** A `replace` whose pattern uses the literal `-1` silently fails to
match, and the failure surfaces later as an unhelpful `lia` error:

```coq
replace (-1 + (1 + z))%Z with z by lia.        (* WRONG - does not match *)
replace (- (1) + (1 + z))%Z with z by lia.     (* right *)
```

**`replace` that matches nothing does not always error.** It can appear to succeed and leave
the goal untouched. If a later `lia` fails inexplicably, check that your `replace` actually
fired.

**`%Z` scope annotations are required** on integer literals and operators in goal positions.

## Debugging

Insert `Show.` anywhere to print the goal state at that point, then re-run:

```coq
  replace (- (1) + (1 + z))%Z with z by lia.
  Show.
  lia.
```

Iterate with the script rather than through Frama-C — about 1s instead of 15s:

```sh
scripts/coq-iter.sh .wp-session/interactive/lemma_sum_pos.v
```

## Error messages

| Coq says | Cause |
|---|---|
| `Tactic failure: Cannot find witness.` | `lia` lacks a hypothesis. Add `Show.` before it and read the context. Often an `is_sint32*` hypothesis was never `intros`ed, or a `replace` did not fire. |
| `The reference Q_Foo was not found` | wrong lemma name — check the preamble for the `_1_` suffix |
| `Unable to unify` | a `rewrite` pattern does not match; check literal printing |
| `Attempt to save an incomplete proof` | a bullet was left unclosed |

## Worked end-to-end example

ACSL:

```c
/*@ logic integer sum(integer n) = n <= 0 ? 0 : n + sum(n-1); */
/*@ lemma sum0: sum(0) == 0; */
/*@ lemma sumn: \forall integer n; n > 0 ==> sum(n) == n + sum(n-1); */
/*@ lemma sum_pos: \forall integer n; n >= 0 ==> sum(n) >= 0; */
```

`sum0`/`sumn` are the base and step lemmas the proof rewrites with, as `Q_sum0`/`Q_sumn`.
The Coq proof that closes it, verified:

```coq
Proof.
Require Import Psatz.
Require Import ZArith.
intros i h1.
apply natlike_rec2 with (z := i); auto with zarith.
- rewrite Q_sum0. lia.
- intros z Hz IHz.
  replace (Z.succ z) with (1 + z)%Z by lia.
  rewrite <- Q_sumn by lia.
  replace (- (1) + (1 + z))%Z with z by lia.
  lia.
Qed.
```

Before writing anything like this: the same property proves **fully automatically** as a
lemma function (`frama-c-wp/references/auto-active.md`). Check that route first.
