# Recommended project layout

Nothing here is enforced by WP. It is the layout that keeps the other rules cheap to follow.

```
project/
├── typedefs.h                 value_type, size_type, *_MAX  -- one pair, project-wide
├── Logic/
│   ├── Count.acsl             shared logic functions, predicates, lemmas
│   └── Unchanged.acsl         guarded like C headers, included from annotations
├── core/
│   ├── find.h                 CONTRACT on the prototype
│   └── find.c                 body + loop annotations only
├── shell/                     unverified: malloc, I/O, volatile, casts, asm
└── .wp-session/               proof cache, Coq scripts, tactic scripts
```

## One typedef pair, project-wide

```c
typedef int value_type;           #define VALUE_TYPE_MAX INT_MAX
typedef unsigned int size_type;   #define SIZE_TYPE_MAX  UINT_MAX
```

One pair means one set of bound lemmas is reusable everywhere. Mixed `int`/`size_t`/`unsigned`
explodes into downcast goals at every step. Starting point:
`acsl-spec/assets/typedefs.h`.

## Rules

**Contract in the header, annotations in the `.c`.** WP reads callers modularly from the
contract alone; the body is never consulted across a call boundary. This is also why every
callee needs a contract even when its source is right there.

A contract left in the `.c` does not fail loudly. Callers in other translation units see a
bare prototype, WP invents a default spec for it, and the run reports `annot:missing-spec
<header>:<line>` among everything else. The symptom at the call site looks like the callee's
postcondition being unusable — easy to misread as a memory-model or cast problem when it is
simply not there. Grep for `annot:missing-spec` before theorising.

**Shared logic in guarded `.acsl` files.**

```c
#ifndef COUNT_ACSL_INCLUDED
#define COUNT_ACSL_INCLUDED
#include "Equal.acsl"
/*@ logic integer Count(...) = ...; */
#endif
```

These are `#include`d from inside annotations, so the run **must** pass `-pp-annot`. Without
it the include silently does nothing and your predicates are undefined, with no error pointing
at the cause. `frama-c-wp/scripts/wp.sh` always passes it.

Include paths reach the preprocessor through `-cpp-extra-args`, which `wp.sh` builds from its
repeatable `-I` option:

```sh
frama-c-wp/scripts/wp.sh -I. -Iinclude -ILogic core/find.c
```

**One definition per fact.** Caller and callee must see the *same* predicate, not two
equivalent ones — the solver matches syntactically far more often than it reasons semantically.

**Session directory.** Keep one per project and reuse it. It holds the proof cache, so a
re-run only proves what changed; it also holds `interactive/*.v` Coq proofs and
`script/*.json` tactic scripts, both of which are source and belong in version control.

`cache/` is a judgement call. By default leave it out: it is machine-generated, it rots, and
it is rewritten wholesale on every reproof. Commit it only when replaying the proof without
provers installed is a goal of the project — then `-wp-cache offline` re-checks every claim
and never calls a solver. If you do commit it, prune it first to the goals of the functions
you actually claim as proved (`frama-c-wp/references/toolchain.md` `## Proof cache`), and
keep the tree out of everyday diffs:

```
sessions/** -diff linguist-generated=true
```

in `.gitattributes` stops `git diff` and `git log -p` from printing thousands of generated
JSON files and stops the host counting them as project source. `git diff --text -- sessions/`
still shows them when you actually want to look.

Invalidate the cache when Frama-C or a prover is upgraded — cached results were produced by a
different tool.

## Build integration

Drive proofs from the build system, one target per verified file, with the flag set in exactly
one shared place. Take a per-function timeout override where a single function needs it, and
keep the `-wp-report-json` output checked in, so a regression shows up as a diff rather than
as a number someone has to notice.
