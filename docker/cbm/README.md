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
./cbm.sh mcp-config   # write mcp-server/configs/.mcp.json + root symlink
./cbm.sh verify       # isolation, UI and MCP handshake checks
```

Then restart Claude Code so it picks up `.mcp.json`.

You do not start the container by hand afterwards: it runs with
`restart: unless-stopped`, so docker brings it back on boot, and the `.mcp.json`
entry launches `./cbm.sh serve-mcp`, which starts it first if it is down.

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

`3rdparty/` is not a repo but a directory *of* repos, so `index` descends into
it and gives each vendored upstream its own graph alongside the first-party
projects (`CBM_VENDOR_DIR` renames the directory it looks for). They are read
just as often as our own code — CBM itself is checked out there — so they are
worth the index.

Pass the project name in queries (`{"project": "…-jen_plate_reader"}`).

## How the pieces fit

| Piece | Where |
|---|---|
| Image build | `Dockerfile` (context: the CBM checkout; entrypoint arrives as the named build context `cbmdocker`) |
| Container shape | `docker-compose.yml` |
| Everything you type | `cbm.sh` |
| Token monitoring | `otelcol.yaml`, `prometheus.yml` (compose profile `metrics`) |
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
mcp-config             Write mcp-server/configs/.mcp.json (+ root symlink)
serve-mcp              Speak MCP on stdio, starting the container if needed
tokens [--all]         Where this project's context went (see below)
metrics <sub>          Token monitoring: OTLP collector + Prometheus
verify                 Egress blocked · DNS blocked · UI up · MCP handshake
harden                 Print the optional sudo iptables rules
```

`.env` is generated by `cbm.sh` on every run (workspace path, uid/gid, port) so
a plain `docker compose` in this directory behaves identically.


## Tracking what it costs (and saves)

Three views, cheapest first.

**1. In-session, no setup** — `/context` shows the context-window breakdown,
including how many tokens the MCP tool *definitions* occupy; `/cost` shows the
session totals.

**2. This workspace's own report** — `./cbm.sh tokens` reads Claude Code's
transcripts for this project and prints where the context went. Note that
`token-report.py` was deleted in `c8a8b2c`, so the command currently says so and
points at the `metrics` profile below; restore the script to use it:

```
./cbm.sh tokens            # the most recent session
./cbm.sh tokens --all      # every session recorded for this workspace
```

Model totals are exact (each assistant message carries a `usage` block). The
per-tool split is estimated from payload size at ~4 bytes/token, because the API
never attributes tokens to an individual tool call. What it answers is the
question that matters here: how much context went into *graph queries* versus
*reading files by hand*.

The baseline recorded before the graph was connected — 13 sessions, no MCP:

```
file exploration       597.2k tok   95.7%  1616 calls
code graph (MCP)            0 tok    0.0%     0 calls
```

**3. Exact per-tool attribution — the `metrics` profile.**
Claude Code's OpenTelemetry metrics *do* attribute tokens per MCP server and
tool: `claude_code.token.usage` carries `mcp_server.name` and `mcp_tool.name`
alongside `type` (input/output/cacheRead/cacheCreation) and `model`. Two extra
containers turn that into history:

```bash
./cbm.sh metrics up                      # OTLP collector + Prometheus
eval "$(./cbm.sh metrics env --export)"  # then restart Claude Code
./cbm.sh metrics tokens                  # by kind, model, MCP server, MCP tool
```

```
up                     Start the collector and Prometheus
down [--volumes]       Stop them; --volumes also drops the metric history
status                 Containers, endpoints, scrape targets, series count
logs [-f]              Collector + Prometheus logs
env [--export]         The OTEL_* settings Claude Code needs
tokens                 Token totals by kind, model, MCP server and MCP tool
query EXPR             One instant PromQL query
open                   Print (and open) http://localhost:9090
```

*Why a collector and not Prometheus alone.* A Claude Code session is a
short-lived process that **pushes**; Prometheus **pulls**. Scraping sessions
directly would miss every session that starts and ends between two scrapes, and
concurrent sessions would fight over one exporter port. So sessions push OTLP to
the collector on `127.0.0.1:4317`, the collector holds the counters
(`metric_expiration: 168h` — the default 5m drops a finished session's totals
before they get interesting), and Prometheus scrapes that one stable target.
Both containers publish to host loopback only and sit on a masquerade-free
bridge: the same no-egress posture as `cbm` itself.

*The settings matter.* `OTEL_LOG_TOOL_DETAILS=1` is not optional here — without
it the name of a *user-configured* MCP server is redacted, this server reads as
`custom`, and the attribution the stack exists for is lost.
`OTEL_METRIC_EXPORT_INTERVAL=10000` shortens the 60s default so a session
shorter than a minute still exports. Put both in `.claude/settings.json` under
`"env"` to have them apply to every session started in this workspace.

Useful PromQL, once data is flowing:

```promql
# graph queries vs everything else, in tokens
sum by (mcp_server_name) (claude_code_token_usage_tokens_total)

# cache reads are the cheap ones — check the split before drawing conclusions
sum by (type) (claude_code_token_usage_tokens_total)

# dollars
sum by (model) (claude_code_cost_usage_USD_total)
```

History lives in the `cbm-prometheus-data` volume, 90 days by default
(`CBM_PROM_RETENTION`). `./cbm.sh metrics down` keeps it; `down --volumes`
deletes it.

## Notes

* `codebase-memory-mcp install` is deliberately **not** run — it would rewrite
  agent config files across the machine. `./cbm.sh mcp-config` writes the one
  entry this workspace needs, and nothing else.
* Claude Code auto-discovers `.mcp.json` **only at the project root**, so the
  canonical file lives in `mcp-server/configs/.mcp.json` and the root
  `.mcp.json` is a symlink to it. Moving the real file to the root instead also
  works; a config that exists *only* under `mcp-server/` is never loaded.
* The mount is read-only, which also means CBM's ADR-writing tools cannot write
  into the repo. Drop the `:ro` suffix in `docker-compose.yml` if you ever want
  them.
* Re-index after large changes with `./cbm.sh index`; the index lives in the
  `cbm-cache` volume and survives restarts and rebuilds.
* `/tmp` is a tmpfs: daemon sockets and identity/lock metadata are discarded
  when the container stops. Persisting these across a host reboot can leave
  startup failing with `CBM daemon could not start within 30000 ms`. To apply
  this mount to an existing container, run `./cbm.sh restart`; the `cbm-cache`
  volume and its indexes are retained.
* `./cbm.sh tool` pipes its JSON over stdin — the supported form; a positional
  JSON blob is deprecated upstream. Example:
  `./cbm.sh tool search_graph '{"project":"…-jen_plate_reader","name_pattern":"Detection","limit":5}'`
* Upgrading CBM: update the submodule, then `./cbm.sh build && ./cbm.sh restart`.
  All CBM processes must run the same build, so restart rather than mixing.

## UI password

The hardened fork requires HTTP Basic authentication for the UI and its APIs.
Use username `cbm` and the `CBM_UI_PASSWORD` value in `docker/cbm/.env`.
The launcher generates a random password once, preserves it on later runs, and
keeps `.env` owner-readable only. This ignored file must never be committed.
Rebuild and recreate the container after updating the fork; password changes
also require recreating the container. Stdio MCP does not use this password.
