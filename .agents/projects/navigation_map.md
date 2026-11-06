# Project skill map

Read these by path; the preserved project configuration lives outside the
normal workspace skill root. Read `project` first, then the skills relevant
to the task. Repeated names such as `project` stay scoped to their directories.
`codebase_mcp` maps to `3rdparty/codebase-memory-mcp`; other entries map to
the same-named repository. `.template` is an authoring skeleton, not a live
project. The `codebase_mcp` and `mcp-server` orientation skills are partial stubs.

| project | skill | path |
|---|---|---|
| `.template` | `project` | [.template/.agents/skills/project/SKILL.md](.template/.agents/skills/project/SKILL.md) |
| `codebase_mcp` | `project` | [codebase_mcp/.agents/skills/project/SKILL.md](codebase_mcp/.agents/skills/project/SKILL.md) |
| `jen_calibration_manager` | `build` | [jen_calibration_manager/.agents/skills/build/SKILL.md](jen_calibration_manager/.agents/skills/build/SKILL.md) |
| `jen_calibration_manager` | `deploy` | [jen_calibration_manager/.agents/skills/deploy/SKILL.md](jen_calibration_manager/.agents/skills/deploy/SKILL.md) |
| `jen_calibration_manager` | `project` | [jen_calibration_manager/.agents/skills/project/SKILL.md](jen_calibration_manager/.agents/skills/project/SKILL.md) |
| `jen_calibration_manager` | `tester` | [jen_calibration_manager/.agents/skills/tester/SKILL.md](jen_calibration_manager/.agents/skills/tester/SKILL.md) |
| `mcp-server` | `project` | [mcp-server/.agents/skills/project/SKILL.md](mcp-server/.agents/skills/project/SKILL.md) |

Support scripts, YAML and references retain their relative hierarchy. Ticket
text, design notes, examples and build logs are agent-neutral and are shared
with Claude from the workspace root: `.projects/<project>/` holds
`.task_todos/`, `.design_todos/`, `.examples/` and `.errors/` (index:
[../../.projects/README.md](../../.projects/README.md)). Do not add context
files under `.codex/projects/`. Source command shortcuts, hooks and client
settings were not migrated as skills or activated in Codex.
