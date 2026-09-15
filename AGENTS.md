# jo-workspace Codex instructions

## Skills and agents

Before implementation, read the relevant workspace skill using the map in
[.agents/skills/README.md](.agents/skills/README.md). Use `l-cpp` for C++ and
`l-bash` for shell work. Report missing or stub guidance explicitly.

Resolve the project from the files in scope and consult
[.codex/projects/navigation_map.md](.codex/projects/navigation_map.md).
Read its `project` skill and relevant build, tester or deploy skills by path;
their absence from the runtime roster does not mean they are missing.

Agent definitions and the preserved `common/` and `utests-coverage/` groups are
indexed in [.codex/agents/README.md](.codex/agents/README.md). The `a-` skills
provide delegation inputs and the fallback for roles absent from the runtime
roster. Use fresh context and load required skills explicitly.

The prompt verification pipeline is available through `a-verify-prompt` and
`a-prompt-parser`; no Claude prompt hook is installed by this migration.
Respect existing user authorization and higher-priority session instructions
when applying any workflow or approval gate.

## Code context

For code analysis, use the project's `codebase-memory` graph when available;
a parent graph may exclude submodules. Verify findings against working-tree
files. If graph tools are unavailable or stale, say so and use targeted file
search. Configuration-only work can be inspected directly.

## Maintaining this migration

Preserve the directory groups and project scope. Keep skill names equal to
their containing directory, and use the maps for nested resources rather than
duplicating them. The original `.claude` tree remains the migration source.
The file correspondence is recorded in `.codex/migration-map.json`.
