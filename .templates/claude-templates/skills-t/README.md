# Skill templates

Skeletons for the six skill types every project here gets. They contain no
project detail — only the section structure and a one-line note on what belongs
in each section. Filling standard: [HOW-TO-FILL.md](HOW-TO-FILL.md).

Sibling template sets live alongside this one under `claude-templates/`:
`agents-t/`, `commands-t/`.

## Why this is not in `.claude/skills/`

Anything at `.claude/skills/<name>/SKILL.md` is auto-discovered: its name and
description enter every session's skill roster and it becomes invocable.
Templates with placeholder descriptions would pollute that roster. Never copy or
symlink this tree into a `.claude/skills/` directory.

## The six types

| type | answers | shape |
|---|---|---|
| `build` | source → artifact, and what the build errors mean | SKILL.md + `references/` |
| `tester` | tests, lint, coverage, and debugging a failing one | SKILL.md + `references/` |
| `deploy` | run it for real and drive/observe it | SKILL.md + `references/` + `scripts/` + `assets/` |
| `project` | how the codebase is put together | single SKILL.md |
| `sandbox` | where to experiment without breaking anything | single SKILL.md |
| `debug` | attach, trace, diagnose a live or crashed process | single SKILL.md |

## Layout

```
<skill-name>/
├── SKILL.md          # required entry point; the only file, until it is not
├── references/       # read on demand: long, minority-of-runs detail
├── scripts/          # executables Claude runs
└── assets/           # files used as-is (config, fixtures)
```

`SKILL.md` is the entry point — do not add a `main.md` beside it, nothing reads
it. Split into `references/` only when a section is long *and* needed by a
minority of runs; link it with a relative path and say when to read it.

## Scripts

```bash
./claude-templates/skills-t/new-skill.sh <type> <project-path> [skill-name] [--force] [--no-exclude]
```

Creates a new skill from a template. `<project-path>` may be absolute, relative
to your cwd, or relative to the workspace root. Substitutes `{{PROJECT}}`,
optionally renames the skill (frontmatter `name` follows the directory), and
prints the done-check.

```bash
./claude-templates/skills-t/install-skill.sh <skill> <target|--global> [--link] [--force] [--no-exclude]
```

Installs an **already-filled** skill into another project, or into
`~/.claude/skills` with `--global` so it loads from any cwd. `--link` symlinks
instead of copying. It refuses any skill still containing `{{...}}`.

`<skill>` resolves as a path first, then as a template name — and a template is
handed off to `new-skill.sh` rather than refused, so
`install-skill.sh build jen_plate_reader` does the sensible thing. Templates
cannot go `--global` or be `--link`ed; an unfilled skill has no business being
shared.

Both scripts append `.claude/**` to the target repo's `.git/info/exclude` after
writing, so skills are ignored locally without touching the tracked
`.gitignore`. Only ever appends, never creates that file (no exclude file, no
change), never duplicates the line. Suppress with `--no-exclude`.

Shared logic (path resolution, the exclude update) lives in `_lib.sh`, which is
sourced by both and is not run directly.

## Naming: the prefix says what the skill depends on

Every skill here is prefixed by what it depends on — `.claude/CLAUDE.md` is the
authority:

| prefix | dependency | example |
|---|---|---|
| `l-` | language | `l-cpp`, `l-bash` |
| `p-` | project | `p-build`, `p-tester`, `p-deploy` |
| `a-` | agent | `a-verify-cpp`, driving `.claude/agents/cpp-verifier.md` |

The six templates here are all project-scoped, so install them under `p-` using
the third argument, which also rewrites the frontmatter `name` to match:

```bash
./.templates/claude-templates/skills-t/new-skill.sh build jen_plate_reader p-build
```

The directory name is the identity — it is the `/command` and the name an
agent's `skills:` field resolves — so it must always equal `name:`.

## Naming collisions

Same-named skills from different sources shadow each other, and which one wins
depends on the session cwd — `build` currently exists both at the workspace root
and inside `jen_calibration_manager`. Keep the workspace copy generic, the
project copy specific, and each description explicit about its scope. A
genuinely different skill gets a distinct name, not a third `build`.
