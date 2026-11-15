# skills

My agent skills: the ones I write and maintain myself, plus a record of the pre-made skills I install as-is.

## Layout

| Path | What lives there |
| --- | --- |
| [`skills/`](skills/) | Skills I create, build, and maintain, grouped by domain. |
| [`external/`](external/README.md) | A tracked list of third-party skills I use unmodified. Nothing is copied here; each entry points at its source. |

## My skills

| Domain | Skills |
| --- | --- |
| [`software-engineering`](skills/software-engineering/) | None yet |
| [`deep-research`](skills/deep-research/) | [`research`](skills/deep-research/research/SKILL.md), [`publish`](skills/deep-research/publish/SKILL.md) |
| [`meta`](skills/meta/) | [`create-skill`](skills/meta/create-skill/SKILL.md), [`evaluate-skill`](skills/meta/evaluate-skill/SKILL.md) |

## Install my skills

With the [`skills` CLI](https://github.com/vercel-labs/skills):

```bash
npx skills add seven7thirty3five5/skills
```

Or a single skill:

```bash
npx skills add seven7thirty3five5/skills --skill <name>
```

## Add a new skill

Create `skills/<domain>/<name>/SKILL.md`. The directory name must match the `name` in the frontmatter, and skill names must be unique across domains.

## External skills

[`external/README.md`](external/README.md) lists them and has one command to install them all. If I start modifying one, it moves into `skills/` with a `CREDITS.md` naming the original.

## License

[MIT](LICENSE) for everything under `skills/`. External skills keep their own licenses.
