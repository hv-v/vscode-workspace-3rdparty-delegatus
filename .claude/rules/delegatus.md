# Delegatus: one orchestrator for the whole workspace

Applies only when you run under Delegatus — you have its `viewer` MCP tools.
Otherwise skip this file.

Delegatus (`docker/delegatus/`, README there) seats **one orchestrator on the
workspace-root project**, `jo-workspace`, and runs it and its workers inside a
container. Each submodule is a git repository, so Delegatus counts it as a
project of its own and **refuses a seat's `create_task`, `create_pipeline` or
`spawn_agent` aimed at another project's directory**.

- Launch every worker with `cwd` = the workspace root. Name the submodule in
  the task — its path, its `project` skill (`rules/projects.md`), the change.
  The worker edits files there and runs git as `git -C <submodule>`.
- Never pass a submodule directory as `cwd`. Put `crossProjectRequest` in a
  call only when the operator's own message asks for that project's board,
  and quote it.
- Engines are Claude and Codex. Gemini is not a Delegatus engine.
- The container has no Docker and no SSH, and reaches only the Anthropic and
  OpenAI APIs. So: **no code graph** (`cbm.sh` needs Docker) — say so, then
  search with scoped `grep`; no Docker builds or tests (the ROS 2 projects) —
  hand them back to the operator, never build outside Docker; no push.
- The workspace is mounted read-write; secrets and the `.atlassian/` and
  `.gitlab/` mirrors are hidden. Commit only when the operator asks.
