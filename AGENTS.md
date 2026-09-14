# Working on this repository

This repo is a skillset, not an application. It ships five Agent Skills for deductive
verification of C with Frama-C/WP. Nothing here is imported by other code, so the only
things that can break are the documents themselves and the wrapper scripts.

## Layout

```
skills/<name>/SKILL.md          the skill body, loaded whenever the skill fires
skills/<name>/references/*.md   loaded on demand, when SKILL.md points at them
skills/<name>/scripts/*.sh      the Frama-C/WP wrappers
skills/<name>/assets/*          templates a user starts from
skills/<name>/agents/openai.yaml  Codex-specific presentation; harnesses ignore what they don't know
tools/check-docs.sh             the consistency check; run it after any edit
.agents/skills/<name>           symlink into skills/, so Codex loads them here
.claude/skills/<name>           symlink into skills/, so Claude Code loads them here
```

`acsl-verify` is a router and bundles nothing. Every other skill owns its files outright:
no file is duplicated, except `scripts/env.sh`, which `frama-c-wp` and `wp-coq` both need
and which must stay byte-identical between them.
