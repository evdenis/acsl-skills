/* Function contract template. Delete the clauses that do not apply -- but delete them
   deliberately: an omitted `assigns` means "assigns everything", not "assigns nothing". */

#ifndef EXAMPLE_H_INCLUDED
#define EXAMPLE_H_INCLUDED

#include "typedefs.h"          /* value_type, size_type, *_MAX */

/*@
  requires   valid: \valid_read(a + (0..n-1));
  // Only when the function really takes a second buffer -- `b`/`m` must be
  // parameters of the declaration below, or Frama-C rejects the whole contract
  // with "unbound logic variable b".
  // requires sep: \separated(a + (0..n-1), b + (0..m-1));
  requires   bound: n <= SIZE_TYPE_MAX - 1;

  terminates \true;
  exits      \false;
  assigns    \nothing;

  ensures    result: 0 <= \result <= n;

  behavior some:
    assumes  \exists integer i; 0 <= i < n && a[i] == v;
    ensures  found:  0 <= \result < n;
    ensures  hit:    a[\result] == v;
    ensures  first:  \forall integer i; 0 <= i < \result ==> a[i] != v;

  behavior none:
    assumes  \forall integer i; 0 <= i < n ==> a[i] != v;
    ensures  miss:   \result == n;

  complete behaviors;
  disjoint behaviors;
*/
size_type example(const value_type* a, size_type n, value_type v);

#endif /* EXAMPLE_H_INCLUDED */
