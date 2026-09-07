# Skill templates

Skeletons for the six skill types every project here gets. They contain no
project detail — only the section structure and a one-line note on what belongs
in each section. Filling standard: [HOW-TO-FILL.md](HOW-TO-FILL.md).

Sibling template sets live alongside this one under `claude-templates/`:
`agents-t/`, `commands-t/`.

## Where a project's skills go

`.claude/CLAUDE.md` is the authority; the short form:

```
<workspace>/.claude/projects/<project root directory name>/.claude/
├── skills/          <- what these templates produce
├── commands/
└── agents/
```

**The directory under `.claude/projects/` is always the project's own root
directory name, spelled identically** — `jen_calibration_manager/` in the
workspace is served by `.claude/projects/jen_calibration_manager/`. Both
scripts derive that name with `basename` rather than accepting it as an
argument, so a skill cannot end up filed under a name that does not match a
project.

Nothing is ever written inside the project repo: those are submodules with
their own history, and workspace tooling has no business in their diffs. That
is also why neither script touches `.git/info/exclude` any more.

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
./templates/claude-templates/skills-t/new-skill.sh <type> <project-path> [skill-name] [--force]
```

Creates a new skill from a template. `<project-path>` may be absolute, relative
to your cwd, or relative to the workspace root, and **must exist** — its
basename is the key the skill is filed under, so a typo would silently create an
orphaned project entry. Substitutes `{{PROJECT}}`, optionally renames the skill
(frontmatter `name` follows the directory), and prints the done-check.

```bash
./templates/claude-templates/skills-t/install-skill.sh <skill> <target|--global> [--link] [--force]
```

Installs an **already-filled** skill for another project, or into
`~/.claude/skills` with `--global` so it loads from any cwd. `--link` symlinks
instead of copying. It refuses any skill still containing `{{...}}`.

`<skill>` resolves as a path first, then as a template name — and a template is
handed off to `new-skill.sh` rather than refused, so
`install-skill.sh build jen_plate_reader` does the sensible thing. Templates
cannot go `--global` or be `--link`ed; an unfilled skill has no business being
shared.

Shared logic (workspace-root walking, path resolution, the
`.claude/projects/<name>` mapping) lives in `_lib.sh`, which is sourced by both
and is not run directly.

## Naming

Project skills are **not** prefixed — the directory under `.claude/projects/`
already says which project they belong to, so they keep the template's own name
(`build`, `tester`, `deploy`, `project`, `sandbox`, `debug`). The retired `p-`
prefix dates from when every project shared one roster.

Only workspace-wide skills in `.claude/skills/` carry a prefix:

| prefix | dependency | example |
|---|---|---|
| `l-` | language | `l-cpp`, `l-bash` |
| `a-` | agent | `a-verify-cpp`, driving `.claude/agents/cpp-verifier.md` |

The directory name is the identity — it is the `/command` and the name an
agent's `skills:` field resolves — so it must always equal `name:`. The third
argument to `new-skill.sh` rewrites both together:

```bash
./templates/claude-templates/skills-t/new-skill.sh build jen_plate_reader hil-build
```

## Naming collisions

Two projects both having a `build` skill is the normal case and is not a
collision: they live under different `.claude/projects/<project>/` directories
and are read by path. A collision is only possible against
`~/.claude/skills/<name>` — `install-skill.sh` says so when it sees one. Keep
the global copy generic, the project copy specific, and every description
explicit about its scope.
