/* Loop annotation template.
   Order: bounds first, then properties, then loop assigns, then loop variant.
   An invariant must be (1) established on entry, (2) preserved by the body, and
   (3) together with the negated loop condition, strong enough to imply the postcondition.
   Point 3 is the one that is usually missing. */

#include "example.h"

size_type example(const value_type* a, size_type n, value_type v)
{
  /*@
    loop invariant bound: 0 <= i <= n;
    loop invariant miss:  \forall integer k; 0 <= k < i ==> a[k] != v;
    loop assigns i;
    loop variant n-i;
  */
  for (size_type i = 0u; i < n; i++) {
    if (a[i] == v) {
      return i;
    }
  }
  return n;
}

/* In-place mutation: a proven bubble sort's outer loop, whose body is
   for (i = 1u; i < n; ++i).

     loop invariant bound:      1 <= i <= n;
     loop invariant increasing: WeaklyIncreasing(a, n-i+1, n);
     loop invariant upper:      1 < i ==> UpperBound(a, n-i+1, a[n-i+1]);
     loop invariant reorder:    MultisetReorder{Pre,Here}(a, n);
     loop assigns i, a[0..n-1];
     loop variant n-i;

   `reorder` is what stops "sorted" being satisfiable by zeroing the array.
   `upper` is what covers index 0: at exit i == n, so `increasing` only gives
   WeaklyIncreasing(a, 1, n); `upper` supplies a[0] <= a[1]. Drop it and the invariant
   can never imply the postcondition, however long the prover runs. */
