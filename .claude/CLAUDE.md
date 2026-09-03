# jo-workspace

## Skills are mandatory, not optional

`.claude/skills/` holds this workspace's standards. **Before starting any task,
check whether a skill covers it and load it with the Skill tool first.** A
skill's guidance overrides your defaults; when they conflict, the skill wins.

| skill | load it whenever the task involves |
|---|---|
| `bash` | writing, editing or reviewing any shell script or non-trivial shell snippet — `.sh` files, generators, wrappers, CI steps |
| `build` | building, compiling, rebuilding, or diagnosing a build failure in any project here |
| `tester` | running tests, lint or coverage, or debugging a failing test |
| `deploy` | running, launching or smoke-testing a node/container, or confirming a change in the real process |

Rules:

- Load the skill **before** writing the file, not after — its rules shape the
  first draft rather than being retrofitted.
- More than one may apply; load all of them.
- If a relevant skill is **empty or missing**, say so explicitly in your reply
  instead of silently falling back to defaults.
- State in your final message which skills you loaded and how they shaped the
  work. In focus mode the tool calls are invisible, so an unmentioned skill
  reads as an unused one.

Skills are installed machine-wide via symlinks from `~/.claude/skills/`, so they
apply from any working directory, not only from the workspace root.

## Skill authoring

Templates and installer scripts live in `claude-templates/skills-t/` — see its
`README.md` and `HOW-TO-FILL.md`. Create with `new-skill.sh <type> <project>`,
share an already-filled one with `install-skill.sh <skill> <project|--global>`.
Never copy the template tree into a `.claude/skills/` directory: templates are
auto-discovered there and pollute the skill roster with placeholder
descriptions.

## Generated files

`.gitmodules` is generated, not tracked — `./gen-gitmodules.sh` renders it from
the tracked `.gitmodules.t` plus the ignored `.gitparams`. Regenerate after a
fresh clone or any submodule change; never hand-edit `.gitmodules`.
