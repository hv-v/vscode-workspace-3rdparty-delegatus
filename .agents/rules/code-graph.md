---
trigger: always_on
---

# The code graph is mandatory, not optional

The `codebase-memory` MCP server (CBM, run in Docker by `docker/cbm/cbm.sh`) is
the first place to look at code — for every request and every subagent, not
only the ones that sound architectural. One graph query replaces a dozen greps
and, unlike grep, it answers *who calls this*, *what breaks if I change it*,
*where does this path end*.

Antigravity gets the server from the workspace plugin
`.agents/plugins/jo-workspace/mcp_config.json`, not from `.mcp.json` (Claude
Code's file). Plugin servers are namespaced, so the server may show as
`jo-workspace_codebase-memory`; the tool names below are the same.

Order of use:
1. `get_architecture` — orientation in an unfamiliar project, before forming any plan.
2. `search_graph` — find a symbol (class, function, message, node).
3. `trace_path` — relationships: caller ↔ callee, include chains, inheritance.
4. `query_graph` — multi-hop questions the three above cannot express in one shot.
5. `get_code_snippet` / `get_file_outline` — read the source the graph pointed at.
6. `search_code`, then grep — literals, comments, build files, and gaps the index does not cover.

Rules:
- Query the project's own graph, named after its absolute path
  (`home-vhaponov-Documents-jo-workspace-<repo directory name>`). The
  workspace-root graph skips registered submodules.
- If the server is unreachable or the repo is not indexed, say so explicitly
  before falling back to file search. Index with `./docker/cbm/cbm.sh index <project>`.
- The graph is a map of the last index, not working-tree evidence. Cite file:line
  from the working tree.
- A recursive grep or `find -name` over a project tree is denied by the
  `graph-first` hook (`.agents/hooks.json`); scope a legitimate literal search
  to one directory or add `--include`.
