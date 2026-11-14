# skills

My agent skills: the ones I write and maintain myself, plus a record of the pre-made skills I install as-is.

## Layout

| Path | What lives there |
| --- | --- |
| [`skills/`](skills/) | Skills I create, build, and maintain. One directory per skill, each with a `SKILL.md`. |
| [`external/`](external/README.md) | A tracked list of third-party skills I use unmodified. Nothing is copied here; each entry points at its source. |
| [`templates/skill/`](templates/skill/SKILL.md) | Starting point for a new skill. |

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

```bash
cp -R templates/skill skills/<name>
```

Then edit `skills/<name>/SKILL.md`. The directory name must match the `name` in the frontmatter.

## Track an external skill

Add a row to [`external/README.md`](external/README.md) with its source and install command. If I start modifying one, it moves into `skills/` with a `CREDITS.md` naming the original.

## License

[MIT](LICENSE) for everything under `skills/` and `templates/`. External skills keep their own licenses.
