---
name: verifiable-c
description: Design and write new C that Frama-C/WP can actually prove, or refactor existing C to make it provable. Covers the constructs WP cannot handle (irreducible goto loops, pointer casts, unions, malloc, container_of, function pointers, recursive-struct navigation), the preferred provable style, recommended project layout, and what to do with kernel, embedded and legacy code. Use when writing new C intended for verification, when WP aborts on a function, or when asked whether some C can be verified at all.
license: MIT
---

# Writing C that WP can prove

**Requires** Frama-C 33 with the WP plugin to check the claims here; the `frama-c-wp` skill
runs it.

## The governing move

**Split a verified core from an unverified shell.** The core is pure computation over
caller-supplied memory. The shell holds allocation, I/O, `volatile` MMIO, pointer casts,
inline asm and `container_of` navigation.

Every hard blocker below is a shell concern. Done this way, the shell stays small and
auditable and the core is fully provable. Done the other way, nothing is provable.

## Hard requirements

Violate these and WP cannot verify the code, or the result cannot be trusted.

1. **Natural loops only** — `for`, `while`, `do-while`. A `goto` back-edge makes WP abort the
   whole function with `Non-natural loop detected`. Fix this first when adopting WP on existing
   code; nothing else runs until it is gone. Forward `goto` to one cleanup label is fine.
2. **No pointer casts.** `(char*)`, `void*` round-trips and punning produce `Cast with
   incompatible pointers types`, degrade `assigns` to everything, and time out. Verified under
   `Typed`, `Typed+cast`, `Typed+nocast` and `Bytes` alike.
3. **No unions.** Use a tagged struct. Union access warns `might be unsound` and **still reports
   proved** — the most dangerous silent failure available.
4. **Arrays are `T *a, size_type n`** — pointer plus explicit length, never unsized or
   sentinel-terminated.
5. **No dynamic allocation in the core.** `malloc`/`\fresh` are unimplemented. Callers supply
   buffers.
6. **Every callee has a contract**, including `extern` declarations and stubs. Minimum
   `assigns` and `terminates`.
7. **`assigns` on every function and every loop.** Omitting it means everything may change.
8. **No statement contracts** — silently dropped while goals still "prove". Extract a function.
9. **Indirect calls need `//@ calls f, g;`** at the call site.
10. **Recursion needs `terminates` and `decreases`.** Not on the entry point.
11. **Logic signatures use `integer`/`real`, never C `int`.**
12. **Verify with RTE on** and run `-wp-smoke-tests` before believing anything.

## Strong preferences

Flat arrays with index handles over pointer-linked structures · functions under ~50 lines with
one loop · `const` on read-only pointer parameters · `\separated` rather than `restrict` ·
one `value_type`/`size_type` typedef pair project-wide · unsigned indices with the bound stated
in `requires`, except a scan index that can run one past an end, which must be signed · floats
guarded by `\is_finite` · stay on the default `-wp-model Typed`.

Full list with rationale and symptoms: `references/style.md`.

## What actually works

Verified, so you can stop guessing:

| Pattern | Result |
|---|---|
| Bitfields | 5/5 proved — fine |
| Recursion with `decreases` | 12/13 — the miss was a genuine overflow |
| `double` with `\is_finite` | fully proved |
| Struct by value | mostly proved |
| Static global with `assigns` | fully proved |
| Function pointer with `//@ calls` | 16/18 |

Kernel-shaped patterns (`container_of`, `list_head`, byte punning, linked lists) are measured
separately in `references/hostile-c.md`.

## Refactoring order

Applying WP to existing code: kill irreducible loops first (nothing else runs until they
are gone), then carve out the shell, fix the data shape, add callee contracts and
`assigns`, then loop annotations, then RTE and smoke tests, and functional postconditions
last. The numbered list with the rule IDs is in `references/style.md`.

## Be honest about what is out of reach

When a construct blocks verification, name it and describe the restructuring. Do not write a
contract that cannot prove and leave it looking like progress, and do not report a
partially-verified file as verified.

## Closing the loop

Provable-shaped C is not verified C. Once the code or the refactor is in place, specify it with
the `acsl-spec` skill and then return to the `acsl-verify` skill, which owns the run/triage
loop and the done criteria. Stopping at `frama-c-wp/scripts/wp.sh` exit 0 is not done.

## Reference

| Need | Read |
|---|---|
| a rule's rationale, or the symptom you are staring at | `references/style.md` |
| the code is kernel, embedded or legacy you cannot restructure | `references/hostile-c.md` |
| laying out headers, `.acsl` files, the session directory | `references/project-layout.md` |
| WP aborted and you need to know if it ever can work | `frama-c-wp/references/limitations.md` |
| writing the annotations | the `acsl-spec` skill |
