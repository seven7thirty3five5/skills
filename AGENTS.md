# Working in this repository

This repository hosts the owner's agent skills. See [README.md](README.md) for the layout.

- `skills/<domain>/<name>/SKILL.md` is a skill the owner maintains. Domains are `software-engineering`, `deep-research`, and `meta`; ask before adding another.
- The skill directory name must equal the frontmatter `name` (lowercase, hyphenated) and be unique across all domains.
- Do not put templates or drafts inside `skills/`; everything there is installable.
- When adding or removing a skill, update the skills table in `README.md`.
- `external/README.md` only lists third-party skills. Never copy a third-party skill's files into this repository unless the owner is forking it, in which case it goes in `skills/` with a `CREDITS.md`. Keep its install-all command in step with its table.
- Keep `SKILL.md` short. Move long reference material into `references/` and link to it from the instructions.
- The frontmatter `description` decides when a skill triggers: say what it does and when to use it.
