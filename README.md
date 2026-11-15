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
| [`misc`](skills/misc/) | None yet. For skills that belong to no domain or apply across domains. |

## Philosophy

**A skill is the entry point to a complete workflow.** It orchestrates a sequence of steps from start to finish, rather than packaging a single technique.

- **Workflow = session.** A workflow almost always starts and ends in a fresh session.
- **I invoke them, the model doesn't.** Because each skill is a whole workflow, my skills are user-invocable only by default.
- **Steps live in reference files.** When a workflow is a large multi-step process, the skill body orchestrates and each step is defined in its own reference file.
- **Rarely, the whole workflow lives in the skill body.** That is for workflows where the agent has to know every step before it begins.

A skill I write is model-invocable in only two cases:

1. **A promoted step.** A step becomes its own skill only when I want it used outside its workflow. It is then shared by design, and being triggered from other workflows is the intent.
2. **A cross-domain skill.** The skill is naturally relevant across domains. These live in [`misc`](skills/misc/).

None of this applies to [external skills](external/README.md), which I use as their authors wrote them.

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
