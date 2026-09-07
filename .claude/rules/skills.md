# Skills are mandatory, not optional

Skills hold this workspace's standards. **Before starting any task, check
whether a skill covers it and load it with the Skill tool first.** A skill's
guidance overrides your defaults; when they conflict, the skill wins.

There are two homes, and the split is the whole convention:

| home | holds | scope |
|---|---|---|
| `.claude/skills/` | language (`l-`) and agent (`a-`) skills | every project, every cwd |
| `.claude/projects/<project>/.claude/` | one project's `skills/`, `commands/`, `agents/` | that project only |

Project skills are covered in `rules/projects.md`.

## Naming: the prefix says what a workspace skill depends on

| prefix | dependency | meaning |
|---|---|---|
| `l-` | **language** | rules for a language, true in any repo that uses it |
| `a-` | **agent** | an entry point that drives a subagent in `.claude/agents/` |

A skill's directory name is its identity — it is the `/command`, the name the
`skills:` field of an agent resolves, and it must equal the `name:` in its own
frontmatter. Rename the directory and the frontmatter together, never one alone.

Agent files take no prefix; their directory already says what they are. An `a-`
skill and the agent it drives are named for the same job (`a-verify-cpp` →
`cpp-verifier`).

Project skills are **not** prefixed — the directory already says which project
they belong to. The retired `p-` prefix meant "this workspace's projects" back
when they shared one roster; it says nothing now that each project has its own
directory.

## The roster

| skill | where | load it whenever the task involves |
|---|---|---|
| `l-bash` | workspace | writing, editing or reviewing any shell script or non-trivial shell snippet — `.sh` files, generators, wrappers, CI steps |
| `l-cpp` | workspace | writing, editing or reviewing C++, designing a class or its ownership model, or reviewing a C++ diff |
| `a-prompt-parser` | workspace, `common/` | splitting an approved prompt into tasks and detecting the agent for each — runs after `a-verify-prompt`; delegates to the `prompt-parser` agent |
| `a-verify-cpp` | workspace | checking C++ in a repo against `l-cpp` and that repo's guidelines — delegates to the `cpp-verifier` agent |
| `a-verify-prompt` | workspace, `common/` | checking a prompt before acting on it — references, attached names, ambiguous grammar, and the `.claude/limits/` limitations — delegates to the `prompt-verifier` agent |
| `a-cpp-tester` | workspace, `utests-coverage/` | implementing C++ unit tests or widening coverage — the only route to a new C++ test file; delegates to the `cpp-tester` agent |
| `a-py-tester` | workspace, `utests-coverage/` | **empty stub** — the `py-tester` agent is not written yet |
| `build` | project | building, compiling, rebuilding, or diagnosing a build failure |
| `tester` | project | running tests, lint or coverage, or debugging a failing test |
| `deploy` | project | running, launching or smoke-testing a node/container, or confirming a change in the real process |
| `project` | project | orientation: architecture, parameters, services, the state of the design todos |

### Grouping folders

A workspace skill may sit one level deeper, in a folder that names the family it
belongs to rather than a skill of its own:

```
.claude/skills/common/a-verify-prompt/SKILL.md
.claude/skills/common/a-prompt-parser/SKILL.md
.claude/skills/utests-coverage/a-cpp-tester/SKILL.md
.claude/skills/utests-coverage/a-py-tester/SKILL.md
```

The grouping folder mirrors the one in `.claude/agents/`, so an agent and the
`a-` skill that drives it are found in the same place under both trees. The
folder itself is not a skill and holds no `SKILL.md`; the skill is still the
directory that contains one, and its name still equals its frontmatter `name:`.

**A grouped skill is not auto-discovered — this is measured, not suspected.**
Moving `a-verify-prompt` into `common/` made `Skill(a-verify-prompt)` fail with
`Unknown skill`. Discovery reads `.claude/skills/<name>/SKILL.md` and goes no
deeper, so a grouped skill is never in the session roster and has no `/command`.

**Read it by path instead** — exactly the convention project skills already use:
an absent name in the roster is not evidence that no skill exists.
`.claude/skills/README.md` is the map from every skill name to its file, and it
is the first thing to check before concluding a skill is missing.

**No symlinks.** A link from the top level into a group would restore discovery,
and it is still the wrong answer: the same skill then exists at two addresses,
git stores a link rather than content, and the tree stops telling the truth
about where a skill lives. Anything that must reach a grouped skill names its
path — the `UserPromptSubmit` hook in `.claude/settings.json` names
`common/a-verify-prompt/SKILL.md` that way.

This does not apply to **agents**: they are discovered at any depth, because an
agent is addressed by its frontmatter `name` rather than its path.
`.claude/agents/common/prompt-parser.md` was picked up with no help at all.

Rules:

- Load the skill **before** writing the file, not after — its rules shape the
  first draft rather than being retrofitted.
- More than one may apply; load all of them. A project task is normally at
  least one `l-` skill plus the project's own skill.
- If a relevant skill is **empty or missing**, say so explicitly in your reply
  instead of silently falling back to defaults.
- State in your final message which skills you loaded and how they shaped the
  work. In focus mode the tool calls are invisible, so an unmentioned skill
  reads as an unused one.

Workspace `l-`/`a-` skills are installed machine-wide via symlinks from
`~/.claude/skills/`, so they apply from any working directory. Project skills
are deliberately not — they are found through `.claude/projects/`.
