# jo-workspace

Instructions for this workspace live in `.claude/rules/`, one file per topic.
Claude Code loads that directory automatically at session start; the
path-scoped files below load only when a matching file is read. This file is
the index and carries the rules that must fire before any file is opened.

## The rules

| file | loads | covers |
|---|---|---|
| `rules/code-graph.md` | always | the `codebase-memory` MCP server: query order, one graph per repo, what to do when it is stale or down |
| `rules/skills.md` | always | the two skill homes, the `l-`/`a-` prefixes, the roster, and the rules for loading them |
| `rules/projects.md` | always | `.claude/projects/<project>/` and the shared `.projects/<project>/` context — the naming rule, the layout, and how to work on a project |
| `rules/atlassian.md` | always | the read-only Jira/Confluence mirror in `.atlassian/`: read it locally, never contact the servers except through `sync.sh` |
| `rules/gitlab.md` | always | the read-only GitLab mirror in `.gitlab/`: MR threads, pipelines, failed-job logs; the pipeline-fix loop; never contact the server except through `sync.sh` |
| `rules/agents.md` | writing an agent | fresh context, no arguments, and the mandatory MCP tool grant |
| `rules/prompt-limits.md` | authoring a limitation, or touching the prompt pipeline | `.claude/limits/`, the file contract, the 1.5× size budget, and the verify → approve → parse → dispatch flow |
| `rules/skill-authoring.md` | touching skills or templates | `new-skill.sh`, `install-skill.sh`, and what never to hand-create |
| `rules/generated-files.md` | touching `.gitmodules` | it is generated; regenerate, never hand-edit |
| `rules/hooks.md` | touching settings or a hook script | which rules the harness enforces, and how to write a hook that fails open |

## Before anything else

1. **Query the code graph first.** `mcp__codebase-memory__*` — for every request
   and every subagent, not only the ones that sound architectural. Never open a
   task with a blind grep or a recursive `find`. Details: `rules/code-graph.md`.
2. **Load the skills that cover the task before writing anything.** A skill's
   guidance overrides your defaults; when they conflict, the skill wins. If a
   relevant skill is empty or missing, say so rather than falling back to
   defaults silently. Skills in a grouping folder (`skills/common/`,
   `skills/utests-coverage/`) are **not** in the session roster — read them by
   path; `.claude/skills/README.md` maps every name to its file. Roster and the
   grouping rule: `rules/skills.md`.
3. **Working on a project?** Resolve its root directory name, then read
   `.claude/projects/<that name>/.claude/skills/*/SKILL.md` **by path** — those
   skills are directory-scoped and never appear in the session roster, so an
   absent skill in the roster is not evidence that none exists. Map of every
   entry: `.claude/projects/navigation_map.md`. Ticket text, design notes and
   examples are agent-neutral and live in `.projects/<that name>/`. Details:
   `rules/projects.md`.
4. **State what you used.** Which skills you loaded and which graph queries you
   leaned on. In focus mode the tool calls are invisible, so an unmentioned
   skill reads as an unused one.

## Maintaining these files

Add a topic by adding a file to `.claude/rules/` and a row above — nothing else
resolves it, and no code changes.

A rule here is context I can skip; a hook in `.claude/settings.json` is enforced
by the harness. When a rule must hold every time, give it a hook too —
`rules/hooks.md` lists which ones have one.

Give a rule `paths:` frontmatter whenever it only matters for part of the tree;
that is the only thing here that actually reduces context, because every
unscoped rule is loaded in full at launch exactly like this file.

Codex and Antigravity read converted copies of this tree from `.agents/` (entry
`AGENTS.md`; Antigravity also `GEMINI.md`). A change to a rule, skill, agent or
hook here should be mirrored there in the same change — `.agents/README.md`
says which file is which.

Do **not** wire the rules in with `@path` imports. Rules already load on their
own, so an import would place the same text in context twice; the paths above
are in backticks precisely so they stay literal. Target under 200 lines for
this file, and keep each rule single-topic.
