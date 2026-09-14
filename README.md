# ACSL / Frama-C / WP skills

A skillset for deductive verification of C with [Frama-C](https://frama-c.com) and its WP
plugin: writing ACSL specifications, running and triaging proofs, getting SMT over the line
without Coq, and writing Coq when there is no other way.

Five skills in the [Agent Skills](https://agentskills.io/specification) format, each a
self-contained directory under `skills/`.

| Skill | Use when |
|---|---|
| `acsl-verify` | entry point — owns the annotate / run / triage / strengthen loop and the definition of done |
| `acsl-spec` | writing or repairing contracts, loop invariants, predicates, lemmas, ghost code |
| `frama-c-wp` | running WP, reading its output correctly, mapping its exact error text to a fix |
| `verifiable-c` | designing C that WP can prove, or deciding whether some C can be verified at all |
| `wp-coq` | manual Coq proofs, after the cheaper tiers have failed |

They route to each other by name, and a few deep links point into another skill's
`references/`, so install the set together rather than one skill on its own.

## Install

```sh
git clone https://github.com/evdenis/acsl-skills
```

Then copy the five directories into whichever skills location your client reads:

| Location | Read by |
|---|---|
| `~/.agents/skills/` | Codex, and other clients using the vendor-neutral path |
| `<project>/.agents/skills/` | the same, for one project |
| `~/.claude/skills/` | Claude Code |
| `<project>/.claude/skills/` | Claude Code, for one project |
| `~/.codex/skills/` | Codex; works, but its source marks this the older location |

```sh
cp -r acsl-skills/skills/* ~/.agents/skills/     # Codex
cp -r acsl-skills/skills/* ~/.claude/skills/     # Claude Code
```

Claude Code can also load the checkout in place, without copying:

```sh
claude --plugin-dir /path/to/acsl-skills
```

This repository carries `.agents/skills` and `.claude/skills` symlinks into its own `skills/`,
so both clients pick the skillset up when you work on the repository itself.

Both clients fire a skill on their own when the task matches its description. To ask for one
by name, Claude Code uses `/acsl-verify` and Codex uses `$acsl-verify`.

Copy all five together. Each skill is self-contained, but several point into another skill's
`references/`, and those pointers assume the five directories sit side by side.

## Requirements

Frama-C 33 with the WP plugin, Why3, and at least Alt-Ergo; CVC5 and Z3 are recommended and
`wp-coq` additionally needs Coq 8.20 with `why3-coq`. The wrapper scripts find the toolchain
themselves — `$FRAMAC_SWITCH` if set, otherwise the opam switch that contains `frama-c`,
otherwise whatever is on `PATH`. Nothing pins a switch name.

## Running the tools

```sh
S=~/.claude/skills                            # wherever the skills landed
$S/frama-c-wp/scripts/wp.sh file.c            # canonical run; exit 0/1/2/3
$S/frama-c-wp/scripts/wp-smoke.sh file.c      # vacuity gate — only after wp.sh exits 0
$S/frama-c-wp/scripts/wp-goal.sh -f fn -p clause -r file.c   # one goal, in detail
$S/wp-coq/scripts/coq-iter.sh <session>/interactive/<goal>.v # fast headless Coq typecheck
```

The skill bodies write these paths relative to their own directory — `scripts/wp.sh`,
`../frama-c-wp/scripts/wp.sh` — which is what the spec prescribes and what Codex resolves.
Each skill says once that the paths need prefixing when the working directory is elsewhere,
and names `${CLAUDE_SKILL_DIR}` for Claude Code, which expands it.

`wp.sh` exits `3` when every goal proved *but* the run carries a soundness finding, because
Frama-C's own exit status is `0` even with goals left unproved.

RTE policy lives in one place, `frama-c-wp/scripts/env.sh`. The two unsigned checks are on by
default; `WP_UNSIGNED=0` (or `wp.sh -U`) drops them for a codebase whose idioms make them
false by construction, and a reduced run says so in its verdict. See
`verifiable-c/references/hostile-c.md`.

## Self-check

The same fact is deliberately stated in more than one place — a `SKILL.md` body is always
loaded once its skill fires, so the common path is restated there rather than hidden behind
a pointer. That is only safe if the copies are checked:

```sh
tools/check-docs.sh        # -q skips the slow checks
```

It validates the frontmatter, checks that every intra- and cross-skill reference resolves,
that no bundled file is orphaned, that the two `env.sh` copies have not diverged, that no
legacy layout paths remain, that the documented prover versions match the installed ones, and
that the templates still typecheck through Frama-C. It also enforces the rules that keep both
clients happy, and runs the `agentskills` validator, Codex's own skill validator and
`claude plugin validate` wherever they are installed. Run it after editing anything here, and
after any Frama-C or prover upgrade.

## Acknowledgements

Two projects taught this skillset most of what it knows, and it would be far thinner without
them. Thanks to both.

- **[ACSL by Example](https://github.com/fraunhoferfokus/acsl-by-example)** (Fraunhofer FOKUS)
  — a large body of carefully specified and proved array algorithms. The house style here is
  theirs: recursive `logic` definitions with named lemmas rather than `axiomatic` blocks,
  contracts on the header, and permutation defined through occurrence counts.
- **[verker](https://github.com/evdenis/verker)** — formally verified Linux kernel library
  functions, and the source of everything here about hostile C: the unsigned RTE carve-out,
  pointer-walking code specified over indices, and the loop-assigns pitfalls.

## License

MIT. See [LICENSE](LICENSE).
