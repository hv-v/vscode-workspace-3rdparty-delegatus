# Agent templates

A subagent is a fresh session: no conversation history, no skills this session
loaded, no arguments. Everything it needs must be in its own file or in the
delegation prompt. `.claude/CLAUDE.md` is the authority; this is the skeleton
and the checklist.

## Where an agent file goes

| scope | path |
|---|---|
| workspace-wide | `.claude/agents/<agent-name>.md` |
| one project | `.claude/projects/<project root directory name>/.claude/agents/<agent-name>.md` |

The directory under `.claude/projects/` is always the project's own root
directory name, spelled identically. Agent files take no prefix — the directory
already says what they are.

## Skeleton

```markdown
---
name: <agent-name>
description: What it does, and `Use when ...` in the words a user would type.
tools: Read, Grep, Glob, Bash,
  mcp__codebase-memory__get_architecture, mcp__codebase-memory__search_graph,
  mcp__codebase-memory__trace_path, mcp__codebase-memory__query_graph,
  mcp__codebase-memory__get_code_snippet, mcp__codebase-memory__get_file_outline,
  mcp__codebase-memory__search_code
skills: l-cpp
model: inherit
permissionMode: default
color: cyan
---

You <one sentence: the job, and the thing you deliberately do not do>.

## Inputs

Subagents receive no arguments. Read these out of the delegation prompt text:

1. **REPO** - ...
2. **...** - ...

State them at the top of your report. If one is missing, say so and stop -
do not substitute a guess.

## How to work

1. Orient with `mcp__codebase-memory__get_architecture` on the project graph
   `home-vhaponov-Documents-jo-workspace-<project>`.
2. ... graph queries before text search ...

## Report format

<the exact shape, so the caller can relay it verbatim>
```

## The three rules that actually bite

1. **Name every skill it needs in `skills:`.** A fresh subagent has none of
   this session's context. An agent reviewing C++ without `skills: l-cpp`
   reviews against generic knowledge, and its report reads identical.
2. **A pinned `tools:` list is exhaustive — MCP included.** Granting the
   `codebase-memory` tools is mandatory for any agent that reads code, and each
   one must be spelled in full; there is no wildcard. Omitting `tools:`
   entirely is the other acceptable answer: the agent then inherits everything,
   MCP included. What is never acceptable is an allowlist that drops the graph
   and leaves the agent grepping.
3. **Values arrive only through the prompt.** That is why each workspace agent
   has a matching `a-` skill (`a-verify-cpp` → `cpp-verifier`) whose job is to
   accept the arguments and format them into the delegation prompt in a fixed
   shape. Write the agent to parse exactly that shape.

A project-scoped agent needs one more line in its body: this project's skills
are at `.claude/projects/<project>/.claude/skills/` and must be read by path,
because directory-scoped skills do not appear in a fresh subagent's roster.

## Worked example

`.claude/agents/cpp-verifier.md` — pinned tools including the five graph tools,
`skills: l-cpp`, inputs parsed out of the prompt, read-only by design, and a
report format its `a-verify-cpp` caller relays verbatim.
