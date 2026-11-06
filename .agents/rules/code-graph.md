---
trigger: always_on
---

# The code graph is mandatory, not optional

The `codebase-memory` MCP server (CBM, `docker/cbm/`, wired in by the root `.mcp.json`) is the first place to look at code — for every request and every subagent, not only the ones that sound architectural. One graph query replaces a dozen greps and, unlike grep, it answers *who calls this*, *what breaks if I change it*, *where does this path end*.

Order of use:
1. `mcp__codebase-memory__get_architecture` — orientation in an unfamiliar project, before forming any plan.
2. `mcp__codebase-memory__search_graph` — find a symbol (class, function, message, node).
3. `mcp__codebase-memory__trace_path` — relationships: caller ↔ callee, include chains, inheritance.
4. `mcp__codebase-memory__query_graph` — multi-hop questions the three above cannot express in one shot.
5. `mcp__codebase-memory__get_code_snippet` / `…__get_file_outline` — read the source the graph pointed at.
6. `mcp__codebase-memory__search_code`, then grep — literals, comments, build files, and gaps the index does not cover.

Rules:
- Query the project's own graph, named after its absolute path (`home-vhaponov-Documents-jo-workspace-<repo directory name>`).
- If the server is unreachable or the repo is not indexed, state that explicitly before falling back to file search/grep.
- The graph is a map of the last index, not working-tree evidence. Cite file:line from the working tree.
