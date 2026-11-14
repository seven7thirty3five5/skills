# Working in this repository

This repository hosts the owner's agent skills. See [README.md](README.md) for the layout.

- `skills/<name>/SKILL.md` is a skill the owner maintains. The directory name must equal the frontmatter `name` (lowercase, hyphenated).
- New skills start from `templates/skill/`. Do not put templates or drafts inside `skills/`; everything there is installable.
- `external/README.md` only lists third-party skills. Never copy a third-party skill's files into this repository unless the owner is forking it, in which case it goes in `skills/` with a `CREDITS.md`.
- Keep `SKILL.md` short. Move long reference material into `references/` and link to it from the instructions.
- The frontmatter `description` decides when a skill triggers: say what it does and when to use it.
