# jo-workspace

## The code graph is mandatory, not optional

The `codebase-memory` MCP server (**CBM**, `docker/cbm/`, wired in by the
root `.mcp.json` symlink) is the first place to look at code — **for every
request and every subagent, not only the ones that sound architectural**. One
graph query replaces a dozen greps and, unlike grep, it answers *who calls
this*, *what breaks if I change it*, *where does this path end*.

Order of use:

1. `mcp__codebase-memory__get_architecture` — orientation in an unfamiliar
   project, before forming any plan.
2. `mcp__codebase-memory__search_graph` — find a symbol (class, function,
   message, node).
3. `mcp__codebase-memory__trace_path` — relationships: caller ↔ callee,
   include chains, inheritance.
4. `mcp__codebase-memory__query_graph` — multi-hop questions the three above
   cannot express in one shot.
5. `mcp__codebase-memory__get_code_snippet` / `…__get_file_outline` — read the
   source the graph pointed at.
6. `mcp__codebase-memory__search_code`, then grep — literals, comments, build
   files, and gaps the index does not cover.

Rules:

- **Never open a task with a blind grep or a recursive `find` over a project.**
  Query the graph first; fall back to text search only for what the graph
  cannot hold (string literals, YAML, CMake, docs) or when
  `…__check_index_coverage` says the cited paths are not indexed.
- **One graph per repository.** Every submodule is its own project, named
  after its absolute path: `home-vhaponov-Documents-jo-workspace`,
  `…-jen_calibration_manager`, `…-jen_plate_reader`, and so on. Pass the right
  one as `{"project": "…"}` — the workspace-root graph sees almost nothing,
  because a parent index skips its registered submodules.
- **A stale or missing index is a fixable condition, not an excuse.** Check
  with `…__index_status`; re-index with `./docker/cbm/cbm.sh index [PATH]`.
  If the server itself is unreachable, say so explicitly in your reply before
  falling back to grep — a silent fallback reads as a graph-backed answer.
- **Every subagent that reads code gets the graph.** See *Agents* below.
- State in your final message which graph queries you leaned on. In focus mode
  the tool calls are invisible.

## Skills are mandatory, not optional

Skills hold this workspace's standards. **Before starting any task, check
whether a skill covers it and load it with the Skill tool first.** A skill's
guidance overrides your defaults; when they conflict, the skill wins.

There are two homes, and the split is the whole convention:

| home | holds | scope |
|---|---|---|
| `.claude/skills/` | language (`l-`) and agent (`a-`) skills | every project, every cwd |
| `.claude/projects/<project>/.claude/` | one project's `skills/`, `commands/`, `agents/` | that project only |

### Project skills live in `.claude/projects/`, never in the project repo

`<project>` **is always the project's root directory name, spelled
identically** — `jen_calibration_manager/` in the workspace is served by
`.claude/projects/jen_calibration_manager/.claude/`. No prefix, no shortening,
no plural. That one-to-one mapping is how a project's configuration is found,
so it is a hard rule: if the repo directory is renamed, rename this one in the
same commit.

```
.claude/projects/jen_calibration_manager/.claude/
├── skills/{build,tester,deploy,project}/SKILL.md
├── commands/{build,tester}/*.md
└── agents/*.md
```

**Start at [`.claude/projects/navigation_map.md`](projects/navigation_map.md)** —
it maps every entry to its repo, its code graph and what is actually filled in
versus still a stub. `.claude/projects/.template/` is the skeleton to copy when
a project joins.

Why here and not inside the repo: the project repos are submodules with their
own history, and workspace tooling has no business appearing in their diffs.
The layout also keeps the alternate contexts of a project (`.design_todos/`,
`.task_todos/`, `.examples/`) beside its skills.

Working on a project:

1. Resolve the project root directory name from the files you are touching, and
   check it against the navigation map.
2. Read `.claude/projects/<that name>/.claude/skills/*/SKILL.md` — these are
   directory-scoped and do not appear in the session's skill roster, so read
   them by path rather than assuming an absent skill means none exists. A file
   carrying a `> **STUB.**` banner records only verified facts: use it as a
   starting point, not as an account of behaviour, and fill in what you learn.
3. Load the workspace `l-` skills for the languages involved.

Project skills are **not** prefixed — the directory already says which project
they belong to. The retired `p-` prefix meant "this workspace's projects" back
when they shared one roster; it says nothing now that each project has its own
directory.

### Naming: the prefix says what a workspace skill depends on

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

### The roster

| skill | where | load it whenever the task involves |
|---|---|---|
| `l-bash` | workspace | writing, editing or reviewing any shell script or non-trivial shell snippet — `.sh` files, generators, wrappers, CI steps |
| `l-cpp` | workspace | writing, editing or reviewing C++, designing a class or its ownership model, or reviewing a C++ diff |
| `a-verify-cpp` | workspace | checking C++ in a repo against `l-cpp` and that repo's guidelines — delegates to the `cpp-verifier` agent |
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

## Agents

`.claude/agents/*.md` hold workspace subagent definitions; a project's own
agents live in `.claude/projects/<project>/.claude/agents/`. Three properties of
subagents drive how they must be written:

- They start with **fresh context** — no conversation history, no skills this
  session already loaded. Any skill an agent needs must be named in its `skills:`
  frontmatter field, or it will work from generic knowledge instead of ours.
- They **take no arguments**. Values reach them only through the delegation
  prompt, which is why each agent has a matching `a-` skill that accepts the
  arguments and formats them into that prompt.
- An agent whose `tools:` field pins an allowlist gets **only** what that list
  names — MCP tools included. **Granting the code graph is mandatory for any
  agent that reads code**, and the tools must be spelled in full:

  ```yaml
  tools: Read, Grep, Glob, Bash,
    mcp__codebase-memory__search_graph, mcp__codebase-memory__trace_path,
    mcp__codebase-memory__query_graph, mcp__codebase-memory__get_architecture,
    mcp__codebase-memory__get_code_snippet, mcp__codebase-memory__get_file_outline,
    mcp__codebase-memory__search_code
  ```

  Omit `tools:` entirely and the agent inherits everything, MCP included — which
  is the other acceptable answer. What is not acceptable is an allowlist that
  quietly drops the graph and leaves the agent grepping.
- A project-scoped agent must also be told, in its own body, that the project's
  skills live at `.claude/projects/<project>/.claude/skills/` and must be read
  by path — a fresh subagent will not find them otherwise.

## Skill authoring

Templates and installer scripts live in `templates/claude-templates/skills-t/` —
see its `README.md` and `HOW-TO-FILL.md`. Create with
`new-skill.sh <type> <project>`, share an already-filled one with
`install-skill.sh <skill> <project|--global>`. Both write into
`.claude/projects/<project>/.claude/skills/`; neither touches the project repo.
Never copy the template tree into a `.claude/skills/` directory: templates are
auto-discovered there and pollute the skill roster with placeholder
descriptions.

## Generated files

`.gitmodules` is generated, not tracked — `./gen-gitmodules.sh` renders it from
the tracked `.gitmodules.t` plus the ignored `.gitparams`. Regenerate after a
fresh clone or any submodule change; never hand-edit `.gitmodules`.
