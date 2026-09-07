# Skill map

Auto-discovery reads `.claude/skills/<name>/SKILL.md` and goes exactly one level
deep. A skill inside a grouping folder is therefore **not** in the session
roster and `Skill(<name>)` fails with `Unknown skill` — the grouping is for
humans reading the tree, and this file is what makes it findable anyway.

**Read a grouped skill by path.** Same convention as project skills: an absent
name in the roster is not evidence the skill does not exist. Look here first.

| skill | path | drives |
|---|---|---|
| `l-bash` | `l-bash/SKILL.md` | — |
| `l-cpp` | `l-cpp/SKILL.md` | — |
| `a-verify-cpp` | `a-verify-cpp/SKILL.md` | `cpp-verifier` |
| `a-verify-prompt` | `common/a-verify-prompt/SKILL.md` | `prompt-verifier` |
| `a-prompt-parser` | `common/a-prompt-parser/SKILL.md` | `prompt-parser` |
| `a-cpp-tester` | `utests-coverage/a-cpp-tester/SKILL.md` | `cpp-tester` |
| `a-py-tester` | `utests-coverage/a-py-tester/SKILL.md` | **empty stub** — no agent yet |

Top-level rows are in the roster and invocable as `/<name>`. Grouped rows are
not; read the file and follow it.

## The groups

| group | holds | mirrors |
|---|---|---|
| `common/` | the prompt pipeline: verify, then split and route | `.claude/agents/common/` |
| `utests-coverage/` | test implementation, one skill per language | `.claude/agents/utests-coverage/` |

A group name matches its folder under `.claude/agents/`, so an agent and the
`a-` skill that drives it sit at the same address in both trees.

## Rules for this file

- **No symlinks.** Do not paper over discovery with a link from the top level
  into a group: it makes the same skill exist at two addresses, and git stores
  the link rather than the content.
- Add a row whenever a skill is added, moved or renamed. This file is the only
  thing that finds a grouped skill; a missing row makes it invisible.
- The `UserPromptSubmit` hook in `.claude/settings.json` names
  `common/a-verify-prompt/SKILL.md` **by path** for this reason. Move that
  directory and the hook must move with it.
- A skill's directory name is still its identity and must equal its frontmatter
  `name:`, grouped or not.
