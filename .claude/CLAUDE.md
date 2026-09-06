# jo-workspace

## Skills are mandatory, not optional

`.claude/skills/` holds this workspace's standards. **Before starting any task,
check whether a skill covers it and load it with the Skill tool first.** A
skill's guidance overrides your defaults; when they conflict, the skill wins.

### Naming: the prefix says what the skill depends on

| prefix | dependency | meaning |
|---|---|---|
| `l-` | **language** | rules for a language, true in any repo that uses it |
| `p-` | **project** | how *this* workspace builds, tests and runs; useless elsewhere |
| `a-` | **agent** | an entry point that drives a subagent in `.claude/agents/` |

A skill's directory name is its identity — it is the `/command`, the name the
`skills:` field of an agent resolves, and it must equal the `name:` in its own
frontmatter. Rename the directory and the frontmatter together, never one alone.

Agent files in `.claude/agents/` take no prefix; their directory already says
what they are. An `a-` skill and the agent it drives are named for the same job
(`a-verify-cpp` → `cpp-verifier`).

### The roster

| skill | load it whenever the task involves |
|---|---|
| `l-bash` | writing, editing or reviewing any shell script or non-trivial shell snippet — `.sh` files, generators, wrappers, CI steps |
| `l-cpp` | writing, editing or reviewing C++, designing a class or its ownership model, or reviewing a C++ diff |
| `a-verify-cpp` | checking C++ in a repo against `l-cpp` and that repo's guidelines — delegates to the `cpp-verifier` agent |
| `p-build` | building, compiling, rebuilding, or diagnosing a build failure in any project here |
| `p-tester` | running tests, lint or coverage, or debugging a failing test |
| `p-deploy` | running, launching or smoke-testing a node/container, or confirming a change in the real process |

Rules:

- Load the skill **before** writing the file, not after — its rules shape the
  first draft rather than being retrofitted.
- More than one may apply; load all of them.
- If a relevant skill is **empty or missing**, say so explicitly in your reply
  instead of silently falling back to defaults.
- State in your final message which skills you loaded and how they shaped the
  work. In focus mode the tool calls are invisible, so an unmentioned skill
  reads as an unused one.

Skills are installed machine-wide via symlinks from `~/.claude/skills/`, so they
apply from any working directory, not only from the workspace root.

## Agents

`.claude/agents/*.md` hold subagent definitions. Two properties of subagents
drive how they must be written:

- They start with **fresh context** — no conversation history, no skills this
  session already loaded. Any skill an agent needs must be named in its `skills:`
  frontmatter field, or it will work from generic knowledge instead of ours.
- They **take no arguments**. Values reach them only through the delegation
  prompt, which is why each agent has a matching `a-` skill that accepts the
  arguments and formats them into that prompt.
- An agent whose `tools:` field pins an allowlist gets **only** what that list
  names — MCP tools included. The code-graph server is `codebase-memory` (see
  `docker/cbm/`), and its tools must be spelled in full to be granted:
  `mcp__codebase-memory__search_graph`, `…__trace_path`,
  `…__get_code_snippet`, `…__get_file_outline`, `…__search_code`. Grant them to
  any agent that explores code — one graph query replaces a dozen greps. Omit
  `tools:` entirely and the agent inherits everything, MCP included.

## Skill authoring

Templates and installer scripts live in `claude-templates/skills-t/` — see its
`README.md` and `HOW-TO-FILL.md`. Create with `new-skill.sh <type> <project>`,
share an already-filled one with `install-skill.sh <skill> <project|--global>`.
Never copy the template tree into a `.claude/skills/` directory: templates are
auto-discovered there and pollute the skill roster with placeholder
descriptions.

## Generated files

`.gitmodules` is generated, not tracked — `./gen-gitmodules.sh` renders it from
the tracked `.gitmodules.t` plus the ignored `.gitparams`. Regenerate after a
fresh clone or any submodule change; never hand-edit `.gitmodules`.
