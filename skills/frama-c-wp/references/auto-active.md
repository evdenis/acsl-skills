# Auto-active proof: getting SMT over the line without Coq

The solver is not searching your codebase. It works from the hypotheses in one verification
condition. A true lemma that is never instantiated is invisible to it. Everything here is about
putting the missing fact where the solver will see it.

Prefer this route over Coq. Codebases that front-load their algebraic lemmas need hand-written
Coq rarely, and one that turns every fact SMT cannot reach into a proved ghost function can
avoid it entirely.

## 1. Guiding assertions

```c
//@ assert bound: 0 <= i && i < n;
//@ assert Count_Union(a, 0, i, n, v);   // instantiate a lemma at these arguments
```

An `assert` is both a goal and, from that point on, a hypothesis. Two uses:

- **Supply a fact** the solver could not find on its own.
- **Bisect a failure** — sprinkle asserts through the function until one fails. That is where
  your reasoning and WP's diverge.

Variants:

| Form | Adds goal | Adds hypothesis | Use |
|---|---|---|---|
| `assert P;` | yes | yes | the normal case |
| `check P;` | yes | no | test whether `P` is provable without strengthening everything after it |
| `admit P;` | no | yes | confirm "if I had this, the rest follows". Every `admit` left behind is an unproved assumption |

Place the assert where the fact is needed, not where it is convenient. A fact asserted after
the loop does not help inside it.

## 2. Lemma functions — induction without Coq

SMT solvers do not do induction. A C function *can*: WP's loop-invariant machinery is an
induction principle. So write a function whose **contract is the lemma** and whose **body is
the proof**. Starting point: `assets/lemma-function.c`.

Verified working, on exactly the lemma that otherwise needs a hand-written Coq script:

```c
/*@ logic integer sum(integer n) = n <= 0 ? 0 : n + sum(n-1); */

/*@ ghost
  /@ requires 0 <= n;
     terminates \true;
     assigns \nothing;
     ensures  sum(n) >= 0;                 // <- this is the lemma
   @/
  void lemma_sum_pos(int n)
  {
    /@ loop invariant bound: 0 <= i <= n;
       loop invariant step:  sum(i) >= 0;  // <- this is the induction hypothesis
       loop assigns i;
       loop variant n - i;
     @/
    for (int i = 0; i < n; i++);           // empty body: the loop exists only to induct
  }
*/

/*@ requires 0 <= k <= 100; assigns \nothing; ensures \result == 1; */
int use(int k)
{
  //@ ghost lemma_sum_pos(k);              // instantiate the lemma here
  //@ assert have: sum(k) >= 0;
  return 1;
}
```

Result: **20/20 goals proved automatically.** The same statement written as
`lemma sum_pos: \forall integer n; n >= 0 ==> sum(n) >= 0;` times out on every SMT prover and
needs a hand-written Coq induction.

Rules:

- `assigns \nothing;` — a lemma function must have no effect.
- The loop body is empty. The loop is scaffolding for the induction, nothing more.
- The invariant is the induction hypothesis; the postcondition follows from it plus the
  negated loop condition.
- Quantified variables that you induct over become **parameters**; the rest stay quantified
  inside the contract.
- Note the syntax: inside `/*@ ghost ... */`, nested annotations use `/@ ... @/`.
- **Ghost code cannot call a non-ghost function** — verified: `Call to non-ghost function from
  ghost code is not allowed`. So declare the lemma function itself `ghost`, or make it an
  ordinary function and call it with an ordinary call.
- **The fact is invisible until you call it.** The `//@ ghost lemma_sum_pos(k);` above is
  mandatory, not illustrative. WP proves the contract once; a caller learns nothing from it
  until that call appears in the caller's own body, at or before the point of need. A proved
  ghost function with no call site is dead weight.
- **Guard the call when the loop condition decides whether it applies.** Walking a string, the
  exiting iteration reads the terminator, where a validity precondition no longer holds.
  Advance the ghost state under the same condition the loop tests, or the ghost call itself
  becomes an unprovable goal on the last step.

## 3. Lemma macros

Try the cheaper move first: most frame obligations need no label-quantified lemma at all —
state the postcondition over `\at(x, Pre)` and carry a pointwise *untouched* invariant. See
`acsl-spec/references/patterns.md` `## Pointer-walking code, specified over indices`.

Lemma functions take C types, so they cannot express a lemma that quantifies over ACSL labels
(a C function has no label parameters). When you need a multi-label lemma, use a macro that
expands to a helper call plus the assertions at the call site:

```c
#define REORDER_STEP(a, n)                        \
  /*@ ghost lemma_reorder_step(a, n); @*/         \
  /*@ assert MultisetReorder{LoopEntry,Here}(a, n); @*/
```

Costs: each expansion adds terms to the proof context, and heavy use slows every goal in the
function. Use sparingly.

## 4. WP tactics

**List them with `-wp-tactic '?'` and `-wp-auto '?'` and copy the name exactly** — an
unregistered name is silently ignored, and the registered set changes between releases. The
useful ones are induction over an integer, lemma and quantifier instantiation, one-step
unfolding, case split, small-range enumeration, arithmetic normalisation, and rewriting with
an equality (spelled `Wp.TacRewrite.Left`/`.Right`, not `Wp.rewrite`).

```sh
# Resolve the toolchain (auto-detects the opam switch holding frama-c;
# override with FRAMAC_SWITCH=<name>). The wrapper scripts do this for you.
. scripts/env.sh

frama-c ... -wp-prover alt-ergo,tip -wp-script init -wp-session S file.c
```

Scripts persist as `S/script/<goal>.json` and replay with `-wp-prover script`. Treat this tier
as optional: it is entirely reasonable to go from lemmas straight to Coq and never write one.

Measured on bit-level goals: the bit strategies do close nibble-range and shift-equality
obligations, but `(hi << 4) | lo == hi * 16 + lo` — disjoint bits implies sum — stalls at
`wp:bitwised` Qed 3/6 even with both operands proved below 16. When a tactic script is the
only thing holding a proof up, rewriting the expression in the source and marking the change
is often the more honest answer: it is a change to the code under verification and should be
read as one.

## 5. Structuring for the solver

- **State the algebraic facts once as `lemma`s.** A recursive `logic` function used directly
  forces the solver to unroll, which times out on anything non-trivial.
- **Keep terms syntactically identical** between caller and callee via one shared `.acsl`
  header — the solver matches syntactically far more often than it reasons semantically.
- **Bound quantifiers tightly**, and split large functions: VC size grows with path count.
- **State the fact in the callee, not the caller.** A caller holding only a pointer difference
  cannot rebuild the pointer (`references/limitations.md` C-11); inside the callee a ghost
  index still exists — `acsl-spec/references/patterns.md`.
