---
paths:
  - ".claude/agents/**"
  - ".claude/projects/**/agents/**"
  - ".claude/skills/a-*/**"
  - ".claude/skills/*/a-*/**"
---

# Writing a subagent

`.claude/agents/**.md` hold workspace subagent definitions; a project's own
agents live in `.claude/projects/<project>/.claude/agents/`. Agents may be
grouped in subdirectories (`common/`, `utests-coverage/`) — the grouping is
organisational only: an agent is addressed by its frontmatter `name`, never by
its path, so names stay unique across the whole tree.

Three properties of subagents drive how they must be written:

- They start with **fresh context** — no conversation history, no skills this
  session already loaded. Any skill an agent needs must be named in its `skills:`
  frontmatter field, or it will work from generic knowledge instead of ours.
- They **take no arguments**. Values reach them only through the delegation
  prompt, which is why each agent has a matching `a-` skill that accepts the
  arguments and formats them into that prompt.
- An agent whose `tools:` field pins an allowlist gets **only** what that list
  names — MCP tools included. **Granting the code graph is mandatory for any
  agent that reads code**, and the tools must be spelled in full:

  ```yaml
  tools: Read, Grep, Glob, Bash,
    mcp__codebase-memory__search_graph, mcp__codebase-memory__trace_path,
    mcp__codebase-memory__query_graph, mcp__codebase-memory__get_architecture,
    mcp__codebase-memory__get_code_snippet, mcp__codebase-memory__get_file_outline,
    mcp__codebase-memory__search_code
  ```

  Omit `tools:` entirely and the agent inherits everything, MCP included — which
  is the other acceptable answer. What is not acceptable is an allowlist that
  quietly drops the graph and leaves the agent grepping.
- A project-scoped agent must also be told, in its own body, that the project's
  skills live at `.claude/projects/<project>/.claude/skills/` and must be read
  by path — a fresh subagent will not find them otherwise.

Templates and the filled-in checklist: `templates/claude-templates/agents-t/`.
