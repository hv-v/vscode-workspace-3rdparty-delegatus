---
trigger: always_on
---

# Subagents and Delegation

Subagents live in `.agents/agents/` (and `.codex/agents/`):
- Subagents start with fresh context. Pass task inputs explicitly in the delegation message.
- Subagents do not take conversational shortcuts: inputs are passed formatted between markers (e.g. `BEGIN PROMPT` / `END PROMPT`, or `REPO:` and `GUIDELINES:`).
- Read-only subagents (`cpp-verifier`, `prompt-verifier`, `prompt-parser`) never modify working-tree files.
- `cpp-tester` writes only into `TEST_DIR` and test registration build files (`test/Sources.cmake`), never into production source files.
