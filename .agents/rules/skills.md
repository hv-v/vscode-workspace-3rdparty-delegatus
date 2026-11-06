---
trigger: always_on
---

# Workspace Skills

Skills hold this workspace's standards. Before starting any task, check whether a skill covers it and follow its instructions. A skill's guidance overrides defaults; when they conflict, the skill wins.

- Skills live in `.agents/skills/`.
- Language skills (`l-cpp`, `l-bash`) enforce language-specific rules across all repositories.
- Agent entry points (`a-verify-cpp`, `a-prompt-parser`, `a-verify-prompt`, `a-cpp-tester`, `a-py-tester`) drive subagents.
- Project-specific skills live under `.agents/projects/<project>/.agents/skills/` (and `.codex/projects/`). Consult `.agents/projects/navigation_map.md`.
- Unimplemented skills (`p-build`, `p-deploy`, `p-tester`, `a-py-tester`) report missing implementation explicitly rather than faking execution.
