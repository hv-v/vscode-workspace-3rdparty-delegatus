# Command templates

A `/command` is a markdown file whose body is the prompt. Frontmatter is what
distinguishes it from a note.

## Where a command file goes

| scope | path | invoked as |
|---|---|---|
| workspace-wide | `.claude/commands/<group>/<name>.md` | `/group:name` |
| one project | `.claude/projects/<project root directory name>/.claude/commands/<group>/<name>.md` | `/group:name` |

The directory under `.claude/projects/` is always the project's own root
directory name, spelled identically.

## Skeleton

```markdown
---
description: One line, imperative - this is what the command list shows.
argument-hint: "[what to type after the command]"
allowed-tools: Bash(docker build:*), Bash(git *), Read
---

<the prompt, written as instructions to Claude>

Arguments arrive as `$ARGUMENTS` (or `$1`, `$2`).
```

## Rules

- **`allowed-tools` is a whitelist, and it is exhaustive.** Scope each `Bash()`
  pattern to the command it actually needs; a bare `Bash` defeats the point. If
  the command explores code, grant the graph tools by full name
  (`mcp__codebase-memory__search_graph`, …) rather than leaving it to grep.
- **A command is a prompt, not a script.** If it is a fixed sequence of shell
  steps, it belongs in a skill's `scripts/` and the command should call it.
- **One job per file.** Group related ones in a subdirectory (`build/image.md`,
  `build/log.md`) instead of branching inside one prompt.
- **Say what "done" looks like** — the line in the output that proves it worked.

## Worked examples

`.claude/projects/jen_calibration_manager/.claude/commands/` — `build/image.md`,
`build/log.md`, `tester/{run,filter,coverage}.md`.
