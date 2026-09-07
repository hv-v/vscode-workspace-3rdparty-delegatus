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
| `a-verify-cpp` | workspace | checking C++ in a repo against `l-cpp` and that repo's guidelines — delegates to the `cpp-verifier` agent |
| `a-verify-prompt` | workspace | checking a prompt before acting on it — references, attached names, ambiguous grammar, and the `.claude/limits/` limitations — delegates to the `prompt-verifier` agent |
| `build` | project | building, compiling, rebuilding, or diagnosing a build failure |
| `tester` | project | running tests, lint or coverage, or debugging a failing test |
| `deploy` | project | running, launching or smoke-testing a node/container, or confirming a change in the real process |
| `project` | project | orientation: architecture, parameters, services, the state of the design todos |

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
