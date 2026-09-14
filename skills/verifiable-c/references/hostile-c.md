# Kernel, embedded and legacy C

Real systems C uses constructs WP handles badly or not at all. This is the measured verdict on
each, plus what to do instead.

The governing move is always the same: **split a verified core from an unverified shell.**
The core is pure computation over caller-supplied memory and is provable. The shell holds the
constructs below and is not verified — but it becomes small, auditable, and explicitly marked.

## Measured verdicts

| Pattern | Measured | Verdict |
|---|---|---|
| Bitfields (`unsigned a : 1;`) | **5/5 proved** | Fine. Use freely. |
| `list_head` doubly-linked splice | **12/13**, one timeout | Workable for a single splice with explicit `assigns` and `\valid` on each touched node. Does not scale to whole-list invariants. |
| `container_of` / `offsetof` cast | type-checks, but `\result == o` round-trip **times out**; two `Cast with incompatible pointers types` warnings | **Unprovable.** The macro's defining property cannot be established under `Typed`. |
| `volatile` MMIO register write | 3/4, one timeout, plus `Memory model hypotheses for function` | Keep in the shell. `-wp-volatile` is on by default and must stay on. |
| Recursive struct + recursive `predicate` | **all 4 goals timed out** | Avoid in the verified core. |
| `(char*)` byte punning | times out under `Typed`, `Typed+cast`, `Typed+nocast`, `Bytes` | **Unprovable.** Shell only. |
| `malloc`/`free`, `\fresh` | `Allocation, initialization and danglingness not yet implemented` | **Unsupported.** Shell only. |
| Function-pointer ops table | 16/18 with `//@ calls f, g;`; `\valid_function` unimplemented | Workable when the callee set is statically known and small. |
| `goto` back-edge | `Non-natural loop detected` — **WP aborts the function** | Must be rewritten before anything can be proved. |
| Inline asm | not analysable | Shell only; give the wrapper a hand-written contract. |

## Linux kernel specifics

**`container_of`.** Its whole point is a pointer cast that `Typed` cannot follow. Do not try to
verify code that navigates by `container_of`. Instead, give the verified function the typed
pointer directly:

```c
/* shell */                          /* verified core */
void handler(struct list_head *e) {  /*@ requires \valid(o); assigns o->a;
  struct outer *o =                      ensures o->a == v; */
    container_of(e, struct outer, in); void core_update(struct outer *o, int v);
  core_update(o, 42);
}
```

The cast stays in one unverified line; everything after it is provable.

**`list_head` chains.** A single insertion or removal proves if you spell out `assigns` for
every node touched and require `\valid` on each. A property over the *whole* list needs a
recursive predicate, which times out. If you need whole-list properties, model the list as a
flat array with index handles in the verified core and keep the chain as the shell's
representation.

**Ops tables (`struct file_operations` and friends).** Each indirect call needs
`//@ calls f, g, h;` naming every possible callee, and all of them need compatible contracts.
This works only when the set is statically known. `\valid_function` is unimplemented, so
"is this a real function pointer" is never checked — record that as an explicit assumption.

**Locking.** WP is sequential. It cannot express or check mutual exclusion. Specify the
function as if the lock is held, state that as a `requires` in prose or via a ghost variable,
and treat the locking discipline as out of scope.

**Byte and counter idioms, and the two unsigned RTE checks.** This is the one place the
standing rule (`references/style.md` H19, `frama-c-wp/references/limitations.md` B-4) is
wrong for kernel code. Two idioms are everywhere in kernel string handling, and both rely on
unsigned wraparound, which is defined behaviour in C:

```c
while (count--)                  /* RTE asserts 0 <= count - 1 before the decrement, */
                                 /* which is false on the last iteration by design    */
c = (unsigned char) *s++;        /* converting a negative char is the entire point    */
```

With `-warn-unsigned-overflow` or `-warn-unsigned-downcast` on, RTE asks these functions to
prove they never do the thing they exist to do. Measured across a kernel string and memory
library: the two options made **19 goals in 11 functions unprovable by construction**. Turn
them off for such a codebase, keep `-wp-rte` itself on, and pay the price honestly:

- name the idiom in the build file, next to the flags, so the drop is not silent;
- say so in the report, per function if only some depend on it;
- remember what you stopped checking. A genuine unsigned bug in that code will not be caught
  by WP, and nothing else will catch it either.

`wp.sh -U` — or `WP_UNSIGNED=0` for `wp-smoke.sh` and `wp-goal.sh`, which read the same policy
from `env.sh` — drops both and keeps `-wp-rte` on. Frama-C emits **no** warning when they are
off (verified), so `wp.sh` prints `REDUCED` itself; without that a reduced run is
indistinguishable from a full one. Do not reach for it anywhere else: outside these idioms a
downcast goal is a real one.

**RCU, per-CPU data, memory barriers.** Out of scope entirely.

## Embedded and bare-metal

**MMIO.** Keep every `volatile` access in the shell. Keep `-wp-volatile` on — `-wp-no-volatile`
makes WP ignore the attribute and is unsound. A verified core that computes *what* to write,
with a thin unverified function that writes it, gets you most of the value.

**No dynamic allocation.** This is an advantage: static buffers with explicit sizes are exactly
the `T *a, size_type n` shape WP wants.

**Fixed-width integer types.** Fine, but pick one pair of project typedefs and stick to it. With
`-warn-unsigned-overflow -warn-unsigned-downcast` on, mixing `uint8_t`, `int`, and `size_t` in
one expression generates downcast goals at every step.

**Interrupt handlers.** Same as locking — WP is sequential. Verify the handler body as an
ordinary function; the concurrency argument is outside the tool.

**Bitfields and bit manipulation.** Bitfields proved cleanly. For bit twiddling, the
`Wp.bitrange` / `Wp.bittestrange` / `Wp.bitwised` tactics and the matching `-wp-auto`
strategies exist. Verdict, measured: they close nibble-range and shift equalities and stall on
anything needing "disjoint bits implies sum" — see `frama-c-wp/references/auto-active.md`
`## 4. WP tactics`, which carries the measurement and the source-rewrite alternative.

## Legacy code you cannot restructure

Work outward, and accept partial coverage:

1. **Run with RTE and no contracts.** The failures are the real runtime-error risks. This is
   useful output on its own.
2. **Minimal contracts.** Add only the `requires` and `assigns` needed to discharge the RTE
   goals. Cheap, modular, and it does not require understanding the full functional intent.
3. **Triage what is out of reach.** A function with an irreducible loop, byte punning or
   `container_of` navigation cannot be specified as-is. Say so explicitly rather than writing a
   contract that will never prove.
4. **Functional specs last**, innermost functions first — a caller cannot be proved before its
   callees have contracts.

Two cautions specific to legacy work:

- `assigns` cannot be skipped even in the minimal-contract approach. It is the one clause that
  callers cannot do without.
- For complex data structures the "minimal" contract collapses into the full functional
  specification, because the RTE goals depend on the structure's invariant. When that happens,
  it is a signal that the data shape needs to change (P9) rather than that you should push
  harder.
