---
name: project
description: STUB (not yet written) - orientation for mcp-server/, which holds the workspace MCP client configuration that records the original Claude MCP client setup and the Codex equivalent. Use when an MCP server is missing, misconfigured, or being added to this workspace.
---

# mcp-server — how it is put together

> **STUB.** Fill it from real runs before relying on it — template:
> `.agents/projects/.template/.agents/skills/project/SKILL.md`, standard:
> the Codex `skill-creator` skill.

Repo: `mcp-server/` (workspace root). Its `README.md` is currently empty.
Code graph: **none, and none is needed** — this is configuration, not code.
Read the files.

## Verified so far

- `mcp-server/configs/.mcp.json` is the real file; the workspace root
  `.mcp.json` is a **symlink** to it. Edit the file, never the symlink target
  path.
- It currently declares one server, `codebase-memory`, launched as
  `docker/cbm/cbm.sh serve-mcp` (which starts the container if it is down).
- That file is **generated**: `./docker/cbm/cbm.sh mcp-config` writes it and
  the root symlink. A hand edit is lost the next time that runs.
- Claude Code reads `.mcp.json` at startup, so a change needs a restart.

## To fill

What else belongs in this config, how a second server would be added without
`mcp-config` overwriting it, and how to tell "server not configured" from
"container down" from "not indexed" when the graph tools stop answering.

## Related

The server itself lives at `3rdparty/codebase-memory-mcp` (see the
`codebase_mcp` entry beside this one) and its container in `docker/cbm/`.

## Codex client

Codex uses `.codex/config.toml`, specifically `[mcp_servers.codebase-memory]`,
which already launches `docker/cbm/cbm.sh serve-mcp`. The `.mcp.json`
procedure above describes the original Claude client only; it does not
configure Codex. Preserve both clients when updating the shared server.
