# `.projects/` — project context, shared by every agent

Ticket text, design notes, examples and build logs for each project. None of it
depends on which agent reads it, so it lives here once instead of being copied
into `.claude/projects/` (Claude Code) and `.agents/projects/` (Codex and
Antigravity). Those trees keep only what is agent-specific: skills, commands
and subagents.

One directory per project, **named exactly like the project's own root
directory** — the same name used under `.claude/projects/` and
`.agents/projects/`. Rename all three together.

```
.projects/<project>/
├── .task_todos/      ticket text, one file per ticket (1619.md)
├── .design_todos/    design notes; the project skill says which are authoritative
├── .examples/        working snippets worth copying, not owned by the repo
└── .errors/          build and run logs kept for diagnosis
```

Create only the directories you need; keep `.gitkeep` in one that is still
empty. `.template/` is the skeleton to copy when a project joins:

```bash
cp -r .projects/.template .projects/<project>
```

Nothing here is written inside the project repo — those are submodules with
their own history.

## Entries

| entry | repo | context |
|---|---|---|
| [jen_calibration_manager](jen_calibration_manager/) | `jen_calibration_manager/` | `.task_todos/` (1590, 1619), `.design_todos/` (1590, 1619, 1757), `.examples/scene_node.md`, `.errors/` |
| [jen_config_manager](jen_config_manager/) | `jen_config_manager/` | `.task_todos/` (SHIRE-1409), `.design_todos/` (SHIRE-1409), `.errors/` |
| [jen_evidence_rules_manager](jen_evidence_rules_manager/) | `jen_evidence_rules_manager/` | `.design_todos/` (1695, SHIRE-1695-review, SHIRE-1695-design-v2-check), `.task_todos/SHIRE-1695-mr-comments.md`, `.examples/SHIRE-1695-enforce-speed-action.md` |
| [codebase_mcp](codebase_mcp/) | `3rdparty/codebase-memory-mcp` | empty |
| [mcp-server](mcp-server/) | `mcp-server/` | empty |
| [.template](.template/) | — | skeleton |

`.gitignore` here re-includes `jen*` entries, which `.git/info/exclude` would
otherwise hide.
