# Workspace skill map

Use `$skill-name` when the skill is in the runtime roster. Otherwise read its
file by path. Grouping folders preserve the source hierarchy; they are not
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
under `.codex/projects/`; consult its navigation map.

Format: https://learn.chatgpt.com/docs/build-skills
