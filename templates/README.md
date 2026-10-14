# templates

Skeletons and installers for everything that gets repeated in this workspace.
`.claude/CLAUDE.md` is the authority on the conventions; these are the shapes
and the scripts.

| set | produces | start at |
|---|---|---|
| [`claude-templates/skills-t/`](claude-templates/skills-t/README.md) | project skills (`build`, `tester`, `deploy`, `project`, `sandbox`, `debug`) | `README.md`, then `HOW-TO-FILL.md` |
| [`claude-templates/agents-t/`](claude-templates/agents-t/README.md) | subagent definitions in `.claude/agents/` | `README.md` |
| [`claude-templates/commands-t/`](claude-templates/commands-t/README.md) | `/commands` | `README.md` |
| [`project-templates/`](project-templates/README.md) | project layout and hierarchy | `HIERARCHY.md` |
| `codex-templates/` | the same conventions for Codex | — |

## The two rules every template here assumes

1. **Project configuration lives at
   `.claude/projects/<project root directory name>/.claude/`** —
   `skills/`, `commands/`, `agents/`. The directory name is the project's own
   root directory name, spelled identically, and nothing is written inside the
   project repo. `skills-t/new-skill.sh` and `install-skill.sh` place files
   there for you; do not hand-create the path. Agent-neutral context —
   ticket text, design notes, examples, logs — goes to the shared
   `.projects/<project>/` instead (skeleton: `.projects/.template/`).
2. **The `codebase-memory` code graph comes first.** Every skill, agent and
   command that reads code is written from graph queries
   (`mcp__codebase-memory__*`) rather than grep output, and any agent or command
   with a pinned tool list must name those tools in full or it will silently
   fall back to text search.

## Quick start

```bash
./templates/claude-templates/skills-t/new-skill.sh build jen_plate_reader
./templates/claude-templates/skills-t/install-skill.sh <skill-dir> <project|--global>
```
