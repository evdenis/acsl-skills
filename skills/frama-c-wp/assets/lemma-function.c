/* Lemma function: prove an inductive property without Coq.
   The contract IS the lemma. The body IS the proof: WP's loop-invariant machinery
   is an induction principle, which SMT solvers do not have.

   Verified: this shape proves 20/20 goals on a property that, written as a plain
   `lemma`, times out on every SMT prover and needs a hand-written Coq script. */

/*@ logic integer sum(integer n) = n <= 0 ? 0 : n + sum(n-1); */

/*@ ghost
  /@ requires 0 <= n;
     terminates \true;
     assigns \nothing;
     ensures  sum(n) >= 0;                  // the lemma being proved
   @/
  void lemma_sum_pos(int n)
  {
    /@ loop invariant bound: 0 <= i <= n;
       loop invariant step:  sum(i) >= 0;   // the induction hypothesis
       loop assigns i;
       loop variant n - i;
     @/
    for (int i = 0; i < n; i++);            // empty body; the loop only drives induction
  }
*/

/* Instantiate it where the fact is needed. Ghost code may only call ghost functions. */
/*@ requires 0 <= k <= 100; assigns \nothing; ensures \result == 1; */
int use(int k)
{
  //@ ghost lemma_sum_pos(k);
  //@ assert have: sum(k) >= 0;
  return 1;
}

/* Checklist:
     - assigns \nothing on the lemma function
     - variables you induct over become C parameters; the rest stay quantified
     - inside /*@ ghost ... *\/, nested annotations use  /@ ... @/
     - if it needs ACSL labels as parameters, a lemma function cannot express it:
       use a lemma macro (references/auto-active.md), or fall back to the wp-coq skill  */
