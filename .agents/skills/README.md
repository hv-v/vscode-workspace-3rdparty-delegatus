# Workspace skill map

Shared by Codex and Antigravity, which both discover `.agents/skills/`. Invoke a
skill in the runtime roster with `$skill-name` (Codex) or `/skill-name`
(Antigravity); otherwise read its file by path. Grouping folders preserve the source hierarchy; they are not
skills themselves. Do not add duplicate copies or symlinks for discovery.

| skill | path |
|---|---|
| `a-verify-cpp` | [a-verify-cpp/SKILL.md](a-verify-cpp/SKILL.md) |
| `a-prompt-parser` | [common/a-prompt-parser/SKILL.md](common/a-prompt-parser/SKILL.md) |
| `a-verify-prompt` | [common/a-verify-prompt/SKILL.md](common/a-verify-prompt/SKILL.md) |
| `l-bash` | [l-bash/SKILL.md](l-bash/SKILL.md) |
| `l-cpp` | [l-cpp/SKILL.md](l-cpp/SKILL.md) |
| `p-build` | [p-build/SKILL.md](p-build/SKILL.md) |
| `p-deploy` | [p-deploy/SKILL.md](p-deploy/SKILL.md) |
| `p-tester` | [p-tester/SKILL.md](p-tester/SKILL.md) |
| `a-cpp-tester` | [utests-coverage/a-cpp-tester/SKILL.md](utests-coverage/a-cpp-tester/SKILL.md) |
| `a-py-tester` | [utests-coverage/a-py-tester/SKILL.md](utests-coverage/a-py-tester/SKILL.md) |

`a-py-tester`, `p-build`, `p-tester`, and `p-deploy` were empty in the source
and remain explicitly unimplemented. Project-specific implementations live
under `.agents/projects/`; consult its navigation map.

These skills are shared: Codex and Antigravity both discover `.agents/skills/`.
Antigravity reaches the grouped ones through `../skills.json`.

Format: https://learn.chatgpt.com/docs/build-skills
