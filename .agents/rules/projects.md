---
trigger: always_on
---

# Project Configuration and Context

Project configuration lives in `.agents/projects/<project>/`, never inside submodule repositories.
Shared project context (ticket text, design notes, examples, logs) lives under `.projects/<project>/`:
- `.task_todos/`
- `.design_todos/`
- `.examples/`
- `.errors/`

Consult `.agents/projects/navigation_map.md` to map repo directories to their skills and graphs.
