# Working in this repository

This repository hosts the owner's agent skills. See [README.md](README.md) for the layout.

- `skills/<domain>/<name>/SKILL.md` is a skill the owner maintains. Domains are `software-engineering`, `deep-research`, `meta`, and `misc`; ask before adding another. `misc` is for skills that belong to no domain or apply across domains.
- The skill directory name must equal the frontmatter `name` (lowercase, hyphenated) and be unique across all domains.
- Do not put templates or drafts inside `skills/`; everything there is installable.
- When adding or removing a skill, update the skills table in `README.md`.
- `external/README.md` only lists third-party skills. Never copy a third-party skill's files into this repository unless the owner is forking it, in which case it goes in `skills/` with a `CREDITS.md`. Keep its install-all command in step with its table.
- The frontmatter `description` says what the skill does and when to use it.

## How the owner's skills are designed

These rules apply to everything under `skills/`, not to external skills.

- A skill is the entry point to a complete workflow. It orchestrates a sequence of steps; it is not a single technique or tip.
- A workflow almost always starts and ends in a fresh session, so write each skill assuming no prior conversation and no follow-on work in the same session.
- Skills are user-invocable only by default: set `disable-model-invocation: true` in the frontmatter.
- For a large multi-step workflow, keep the skill body to the orchestration and define each step in its own file under `references/`.
- Define the whole workflow in the skill body only when the agent must know every step before beginning. This should be rare.
- Promote a step to its own skill only when the owner wants it used outside its workflow. A promoted step is shared by design, so it is model-invocable and other workflows are expected to trigger it.
- A skill is model-invocable in exactly two cases: it is a promoted step, or it is naturally relevant across domains, in which case it lives in `skills/misc/`. Omit `disable-model-invocation` for these and write the `description` so the model knows when to trigger it.
