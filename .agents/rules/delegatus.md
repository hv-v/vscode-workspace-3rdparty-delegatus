---
trigger: always_on
---

# Delegatus: one orchestrator for the whole workspace

Only when you run under Delegatus (you have its `viewer` MCP tools).

- One orchestrator is seated on the workspace-root project, `jo-workspace`.
  Each submodule is its own Delegatus project, and a seat's `create_task`,
  `create_pipeline` or `spawn_agent` into another project's directory is
  refused.
- Launch workers with `cwd` = the workspace root; name the submodule path and
  its `project` skill in the task; run git as `git -C <submodule>`. Use
  `crossProjectRequest` only when the operator asked, quoting them.
- Engines: Claude and Codex only.
- In the container: no Docker (no code graph — say so, then scoped `grep`; no
  Docker builds or tests — hand them back), no SSH, network only to the
  Anthropic and OpenAI APIs. Workspace read-write, secrets and corporate
  mirrors hidden. Commit only when asked.
