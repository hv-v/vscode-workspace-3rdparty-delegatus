# `docker/` — containers this workspace runs

Each directory builds from a clone in `3rdparty/` (git-ignored) and is driven by
its own script. Both use the same network shape: a bridge with IP masquerade
off and DNS black-holed, so nothing leaves the host, and ports published on
`127.0.0.1` only.

| directory | upstream clone | what it serves | start |
|---|---|---|---|
| [cbm/](cbm/README.md) | `3rdparty/codebase-memory-mcp` | the `codebase-memory` code graph: MCP over `docker exec`, graph UI on `:9749` | `./cbm/cbm.sh up` |
| [delegatus/](delegatus/README.md) | `3rdparty/delegatus` | the Delegatus board over your agent transcripts, behind an access key on `:8898` | `./delegatus/delegatus.sh up` |
