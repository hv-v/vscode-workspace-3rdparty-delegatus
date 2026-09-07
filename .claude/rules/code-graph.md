# The code graph is mandatory, not optional

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
- **Every subagent that reads code gets the graph.** See `rules/agents.md`.
- State in your final message which graph queries you leaned on. In focus mode
  the tool calls are invisible.
