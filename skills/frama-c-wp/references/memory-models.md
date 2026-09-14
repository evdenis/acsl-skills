# Memory models

`-wp-model <selector>[+variant...]`. **The default `Typed` is right for nearly everything.
Do not change it to make a warning go away** — a different model rarely fixes a proof and
several of the variants trade soundness for reach.

## Base models

| Selector | What it is | When |
|---|---|---|
| `Typed` | typed pointers, one memory chunk per C type. **The default.** | almost always |
| `Hoare` | logic variables only, no heap at all | pure scalar functions with no pointers; very fast |
| `Bytes` | low-level byte-addressed model — **experimental** | byte punning, in theory. Verified: it did **not** rescue a `char*` punning probe, which timed out under `Bytes` just as under `Typed` |
| `Region` | based on the Region plug-in — **experimental** | rarely |
| `Eva` | uses Eva's value analysis — **experimental** | rarely |

## Variants

| Variant | Effect |
|---|---|
| `+nocast` | reject pointer casts outright |
| `+cast` | accept unsafe pointer casts. Verified: it does **not** silence `Cast with incompatible pointers types`, and did not help the punning probe |
| `+raw` | no logic variables |
| `+ref` | detect by-reference-style pointers — **injects unproved separation hypotheses** |
| `+nat` / `+int` | natural (unbounded) vs machine integer arithmetic |
| `+real` / `+float` | real vs IEEE floating point |

Default is effectively `Typed+var+int+float`.

## The two that can cost you soundness

**`+ref` and `+caveat`.** They make more proofs go through by assuming pointers do not alias.
WP announces this: `Memory model hypotheses for function 'f': ...`. Those hypotheses are
*assumed*, not proved. If you use them, add `-wp-check-memory-model` so they become checked
clauses on the callers. `wp.sh` flags this string as a soundness finding.

**`+cast`.** Relaxes the model's pointer-cast check. It does not silence the diagnostic and,
verified, does not help the case people reach for it for. Treat pointer punning as
unverifiable rather than as a model-selection problem.

## Integer and float variants

`+nat` makes integers unbounded, which removes overflow reasoning. That is not C semantics —
use it only to isolate whether a failure is arithmetic-related, never for a final result.

`+real` treats `float`/`double` as mathematical reals. Also not C semantics. Keep `+float` and
guard float parameters with `\is_finite`, which was verified to prove cleanly.

Separately, `-wp-weak-int-model` is documented by WP itself as "possibly unsound". Never use it.

## Choosing

```
pure scalar arithmetic, no pointers ....... Hoare      (fast)
everything else ........................... Typed      (default)
byte-level punning ........................ do not verify it; move it to the shell
```

If a proof needs a non-default model, that is a signal the C should change — see
`verifiable-c/references/style.md` and `verifiable-c/references/hostile-c.md`.

## Related flags

| Flag | Use |
|---|---|
| `-wp-check-memory-model` | turn `+ref`/`+caveat` assumptions into checked obligations |
| `-wp-ref-vars v,...` | treat named variables as by-reference |
| `-wp-unalias-vars v,...` | assert named variables are not aliased |
| `-wp-volatile` | sound volatile modelling — **on by default, keep it** |
| `-wp-unfold-assigns n` | unfold aggregate `assigns` to depth `n` |
| `-wp-extern-arrays` | invent sizes for `extern T a[]` — an assumption, not a proof |
