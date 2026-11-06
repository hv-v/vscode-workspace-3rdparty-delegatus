---
name: project
description: STUB (not yet written) - orientation for codebase-memory-mcp, the code-graph server behind every mcp__codebase-memory__* tool in this workspace. Use when the graph is stale, unreachable or wrong, or when changing how CBM indexes this workspace.
---

# codebase-memory-mcp — how it is put together

> **STUB.** Fill it from real runs before relying on it — template:
> `.codex/projects/.template/.agents/skills/project/SKILL.md`, standard:
> the Codex `skill-creator` skill.

> **Directory-name mismatch.** The convention in `AGENTS.md` is that a
> directory here is spelled exactly like the project's root directory. The
> checkout is `3rdparty/codebase-memory-mcp`, so this entry should be
> `codebase-memory-mcp`. Left as `codebase_mcp` pending your call:
> The migration preserves `codebase_mcp`; use the explicit repository mapping above.

Repo: `3rdparty/codebase-memory-mcp` — a git submodule
(`git@github.com:vhaponovnix/codebase-mcp.git`, branch `main`), upstream
`DeusData/codebase-memory-mcp`.
Code graph: `home-vhaponov-Documents-jo-workspace-3rdparty-codebase-memory-mcp`
— indexed, 26128 nodes / 131086 edges, by far the largest graph here.

## Verified so far

- Go project: `internal/`, `pkg/`, `build/`, `graph-ui/` (the 3D graph UI),
  `Makefile.cbm`, `flake.nix`, `install.sh` / `install.ps1`.
- **We do not run it from this checkout.** `docker/cbm/` builds it into a
  container that mounts the workspace read-only at its host path, serves the UI
  on `http://localhost:9749`, has no route to the internet, and speaks MCP over
  stdio through `docker exec -i`.
- Everything you type goes through `docker/cbm/cbm.sh`: `build`, `up`, `index`,
  `mcp-config`, `verify`, `status`, `serve-mcp`, `tool`.
- One graph per repository: a parent index skips its registered submodules, so
  `cbm.sh index` with no argument indexes the root *and* each project below it.

## To fill

Which upstream version we are pinned to and why, what a re-index costs in time,
how to read `check_index_coverage` output, and which languages/constructs the
indexer silently skips (the one place a bare grep is the right first move).

## Related

`docker/cbm/README.md` is the operational document and is already written —
read it before this stub. Client config: the `mcp-server` entry beside this one.
