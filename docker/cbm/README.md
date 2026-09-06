# codebase-memory-mcp — isolated container

Runs [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp)
(checked out at `3rdparty/codebase-memory-mcp`) in a container that

* **indexes this workspace read-only**, mounted at the *same absolute path* it
  has on the host, so every path CBM reports is directly usable on the host;
* **serves its 3D graph UI on host loopback** — `http://localhost:9749`;
* **has no route to the internet** — verified, not assumed (`./cbm.sh verify`);
* **speaks MCP over stdio**, through `docker exec -i`, with no network at all.

Agents keep editing files on the host; the container only reads and answers
structural queries.

## Quick start

```bash
./cbm.sh build        # multi-stage build: graph UI + pure-C binary (minutes)
./cbm.sh up           # start; UI on http://localhost:9749
./cbm.sh index        # grant + index the workspace and every project in it
./cbm.sh mcp-config   # register the server in ../../.mcp.json
./cbm.sh verify       # isolation, UI and MCP handshake checks
```

Then restart Claude Code so it picks up `.mcp.json`.

### One graph per repository

CBM indexes a repository into its own project graph and **skips that repo's
registered submodules** — they belong to their own projects. In a workspace of
submodules that means the root index alone sees almost nothing, so `./cbm.sh
index` with no argument indexes the root *and* each project directory below it:

```
home-vhaponov-Documents-jo-workspace                              267 nodes
home-vhaponov-Documents-jo-workspace-jen_calibration_manager    1,103 nodes
home-vhaponov-Documents-jo-workspace-jen_plate_reader           9,139 nodes
home-vhaponov-Documents-jo-workspace-k3s-qemu                      72 nodes
home-vhaponov-Documents-jo-workspace-shire-apps                   127 nodes
```

Pass the project name in queries (`{"project": "…-jen_plate_reader"}`).
`3rdparty/` is gitignored and therefore skipped; index it explicitly with
`./cbm.sh index ../../3rdparty/codebase-memory-mcp` if you ever want it.

## How the pieces fit

| Piece | Where |
|---|---|
| Image build | `Dockerfile` (context: the CBM checkout; entrypoint arrives as the named build context `cbmdocker`) |
| Container shape | `docker-compose.yml` |
| Everything you type | `cbm.sh` |
| Index + config storage | docker volume `cbm-cache` → `/cbm/cache` (`CBM_CACHE_DIR`) |

The image is built from source, not downloaded: stage 1 installs gcc and the
official Node LTS tarball (pinned by SHA-256), runs upstream's own
`scripts/build.sh --with-ui` — which builds `graph-ui` and links it into the
binary — and stage 2 copies just the resulting executable into a compiler-free
runtime image that runs as your uid.

## Three constraints that shaped the design

**1. The UI binds `127.0.0.1` only, on purpose.**
`src/ui/httpd.c` hard-codes the loopback address and rejects any `Host` header
that is not `127.0.0.1:<port>` / `localhost:<port>` — an anti-DNS-rebinding
control. A published docker port DNATs to the container's *bridge* address, which
that listener never sees. The entrypoint therefore runs a `socat` forwarder from
`<bridge-ip>:9749` to `127.0.0.1:9749` — same port on both sides, so the
browser's `Host: localhost:9749` still validates. The container port is
published to host loopback only, so the exposure stays exactly what upstream
intended: local, not remote.

**2. A `--internal` docker network would kill the UI.**
Measured on this host: with `--internal`, egress is blocked *and* published
ports stop working (connection refused). So the network here is an ordinary
bridge with `com.docker.network.bridge.enable_ip_masquerade=false`: without NAT
the container's packets have no return path, egress dies, and port publishing
keeps working. DNS is pointed at `127.0.0.1`, where nothing listens, so name
resolution fails too. `./cbm.sh verify` proves both.

For a hard `DROP` instead of a black hole — which also covers hosts on your LAN
— `./cbm.sh harden` prints the `DOCKER-USER` iptables rules (needs `sudo`).

**3. The server exits when stdin closes.**
That is normal MCP behaviour. The container's main process is therefore one
long-lived CBM session with stdin held open; it owns the shared coordination
daemon, which owns the UI. Each `docker exec -i … codebase-memory-mcp` MCP
session joins that same daemon and cache root — which is why `CBM_CACHE_DIR` is
baked into the image: CBM's admission barrier rejects processes that disagree
about it.

## Commands

```
build [--no-cache]     Build the image
up | down | restart    Lifecycle (down --volumes also drops the index)
status                 Container, health, UI, granted roots
logs [-f]              Container logs
index [PATH]           Grant + index a repo (default: the whole workspace)
tool NAME [JSON]       Run one CBM tool, e.g. tool get_architecture '{}'
ui                     Print (and open) the UI URL
shell                  Shell inside the container
mcp-config             Register the server in the workspace .mcp.json
verify                 Egress blocked · DNS blocked · UI up · MCP handshake
harden                 Print the optional sudo iptables rules
```

`.env` is generated by `cbm.sh` on every run (workspace path, uid/gid, port) so
a plain `docker compose` in this directory behaves identically.

## Notes

* `codebase-memory-mcp install` is deliberately **not** run — it would rewrite
  agent config files across the machine. `./cbm.sh mcp-config` writes the one
  entry this workspace needs, and nothing else.
* The mount is read-only, which also means CBM's ADR-writing tools cannot write
  into the repo. Drop the `:ro` suffix in `docker-compose.yml` if you ever want
  them.
* Re-index after large changes with `./cbm.sh index`; the index lives in the
  `cbm-cache` volume and survives restarts and rebuilds.
* `./cbm.sh tool` pipes its JSON over stdin — the supported form; a positional
  JSON blob is deprecated upstream. Example:
  `./cbm.sh tool search_graph '{"project":"…-jen_plate_reader","name_pattern":"Detection","limit":5}'`
* Upgrading CBM: update the submodule, then `./cbm.sh build && ./cbm.sh restart`.
  All CBM processes must run the same build, so restart rather than mixing.
