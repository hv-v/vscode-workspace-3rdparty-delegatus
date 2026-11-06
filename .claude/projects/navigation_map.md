# `.claude/projects/` — navigation map

Project-scoped configuration for everything in this workspace. One directory
per project, **named exactly like the project's own root directory** — that
mapping is how you find a project's skills, so resolve the directory name from
the files you are touching and come straight here.

These skills are directory-scoped: they do **not** appear in a session's skill
roster, and a fresh subagent will never be offered them. Read them by path.
An absent skill in the roster is not evidence that none exists.

## The map

| entry | repo | what it is | code graph |
|---|---|---|---|
| [jen_calibration_manager](jen_calibration_manager/) | `jen_calibration_manager/` | ROS 2 relay: calibration params → `/tf`, `SetCameraInfo`, `/diagnostics` (SHIRE-1619) | `…-jen_calibration_manager` · 1.1k nodes |
| [jen_config_manager](jen_config_manager/) | `jen_config_manager/` | ROS 2 config manager: schema-validated node parameters (`get/set_node_parameters`), checksums, diagnostics | `…-jen_config_manager` · 2.9k nodes |
| [jen_plate_reader](jen_plate_reader/) | `jen_plate_reader/` | ROS 2 plate reading; the big one — C++/Python, 15 packages around `libalgo` | `…-jen_plate_reader` · 9.1k nodes |
| [jen_scene_manager](jen_scene_manager/) | `jen_scene_manager/` | ROS 2 validating proxy for Scene parameters (`jen_scene_msgs`) | **not indexed** |
| [k3s-qemu](k3s-qemu/) | `k3s-qemu/` | local K3s cluster in a QEMU VM; `ubuntu/` and `shireos/` variants | `…-k3s-qemu` · 72 nodes |
| [shire-apps](shire-apps/) | `shire-apps/` | Helm charts: `shire-base` aggregator + `shire-sr355` / `shire-vector4` | `…-shire-apps` · 127 nodes |
| [mcp-server](mcp-server/) | `mcp-server/` | the generated `.mcp.json` that wires Claude Code to the graph | none needed (config) |
| [codebase_mcp](codebase_mcp/) | `3rdparty/codebase-memory-mcp` | the CBM server itself (Go), run containerized from `docker/cbm/` | `…-3rdparty-codebase-memory-mcp` · 26k nodes |
| delegatus *(no entry yet)* | `3rdparty/delegatus` | agent board and orchestrator (TypeScript, Next.js on Bun), run offline from `docker/delegatus/` | `…-3rdparty-delegatus` · 188k nodes |
| [.template](.template/) | — | the skeleton to copy for a new project | — |

Graph names are the full absolute path with separators flattened; the `…` above
stands for `home-vhaponov-Documents-jo-workspace`. The workspace-root graph
(`home-vhaponov-Documents-jo-workspace`, 309 nodes) sees almost nothing on its
own — a parent index skips its registered submodules — so always pass the
project's own graph.

**`delegatus` has no configuration entry yet** — only the container in `docker/delegatus/` (README there). **Two entries do not match a workspace root directory:** `codebase_mcp` is
`3rdparty/codebase-memory-mcp` (rename pending — see its stub), and `.template`
is a skeleton, not a project.

## What is actually filled in

| entry | project | build | tester | deploy | commands | context |
|---|---|---|---|---|---|---|
| jen_calibration_manager | ✅ | ✅ | ✅ | ✅ + `driver.py` | `build/`, `tester/` | `.projects/jen_calibration_manager/` — `.task_todos/`, `.design_todos/`, `.examples/`, `.errors/` |
| shire-apps | — | — | — | ✅ offline render + umbrella composition | — | — |
| jen_config_manager | — | ✅ | ✅ | — | — | `.projects/jen_config_manager/` — `.task_todos/`, `.design_todos/`, `.errors/` |
| everything else | stub | — | — | — | — | — |

A **stub** carries a `> **STUB.**` banner and a `STUB (not yet written)` prefix
in its description. It records only verified facts and names what is missing.
Treat it as a starting point, never as an account of behaviour — and if you
learn the real answer while working, write it in rather than leaving the stub.

Create a missing skill; do not hand-write one:

```bash
./templates/claude-templates/skills-t/new-skill.sh <build|tester|deploy|project|sandbox|debug> <project>
```

## Working on a project

1. Resolve the project's root directory name from the files in play.
2. Read `.claude/projects/<that name>/.claude/skills/*/SKILL.md` — the
   `project` skill first.
3. Query that project's code graph (`mcp__codebase-memory__*`) before grepping.
   Not indexed? `./docker/cbm/cbm.sh index <project>`.
4. Read the task's context in `.projects/<that name>/` — ticket text, design
   notes, examples.
5. Load the workspace language skills for what you are writing: `l-cpp`,
   `l-bash`.

## Layout of one entry

```
.claude/projects/<project>/       Claude-specific
└── .claude/
    ├── skills/<name>/SKILL.md    project skills, unprefixed
    ├── commands/<group>/<x>.md   /commands scoped to this project
    └── agents/<name>.md          subagents scoped to this project

.projects/<project>/              agent-neutral, shared with Codex
├── .task_todos/                  ticket text, one file per ticket
├── .design_todos/                design notes
├── .examples/                    snippets worth copying, not owned by the repo
└── .errors/                      build and run logs kept for diagnosis
```

Nothing is ever written inside the project repo — those are submodules with
their own history. Nothing agent-neutral is written here either; it goes to
`.projects/` (see `.projects/README.md`).

## Not here

| you want | look in |
|---|---|
| ticket text, design notes, examples, build logs | `.projects/<project>/` |
| language / agent-entry skills (`l-cpp`, `l-bash`, `a-verify-cpp`) | `.claude/skills/` |
| workspace subagents (`cpp-verifier`) | `.claude/agents/` |
| the conventions themselves | `.claude/CLAUDE.md` |
| skill / agent / command templates and installers | `templates/` |
| running, indexing or debugging the graph server | `docker/cbm/README.md` |
