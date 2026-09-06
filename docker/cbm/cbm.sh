#!/usr/bin/env bash
#
# cbm.sh — build, run and verify the isolated codebase-memory-mcp container.
#
# The container indexes this workspace read-only, serves its 3D graph UI on
# host loopback, and speaks MCP over stdio through `docker exec` — it has no
# route to the internet. See README.md for the design.
#
# Usage: ./cbm.sh <command> [options]   ( ./cbm.sh help )

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
readonly compose_file="${script_dir}/docker-compose.yml"
readonly env_file="${script_dir}/.env"

# The workspace root is two levels above docker/cbm.
workspace_dir="$(cd -- "${script_dir}/../.." && pwd)"
readonly workspace_dir
readonly cbm_source_dir="${workspace_dir}/3rdparty/codebase-memory-mcp"

readonly ui_port="${CBM_UI_PORT:-9749}"
readonly container_name="${CBM_CONTAINER:-cbm-server}"
readonly mcp_server_name="${CBM_MCP_NAME:-codebase-memory}"

# Vendored upstreams: not repos of this workspace, but code the agents read,
# so they are indexed too — one level deeper than everything else.
readonly vendor_dir="${CBM_VENDOR_DIR:-3rdparty}"

# Token monitoring (compose profile "metrics"), all on host loopback.
readonly prom_port="${CBM_PROM_PORT:-9090}"
readonly otlp_grpc_port="${CBM_OTLP_GRPC_PORT:-4317}"
readonly otlp_http_port="${CBM_OTLP_HTTP_PORT:-4318}"

# Exit codes: 64 usage, 69 unavailable (docker/container), 70 internal failure.
readonly ex_usage=64
readonly ex_unavailable=69
readonly ex_software=70

tmp_files=()

cleanup() {
    local file
    for file in ${tmp_files[@]+"${tmp_files[@]}"}; do
        rm -f -- "$file"
    done
}
trap cleanup EXIT

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit "${2:-$ex_software}"; }

usage() {
    cat <<'EOF'
Usage: ./cbm.sh <command> [options]

Lifecycle
  build [--no-cache]     Build the image (multi-stage: graph UI + C binary)
  up                     Start the container (builds it first if missing)
  down [--volumes]       Stop it; --volumes also drops the index cache
  restart                Recreate the container
  status                 Container, health, UI and index state
  logs [-f]              Container logs

Use
  index [PATH]           Grant + index a repo (default: the whole workspace)
  tool NAME [JSON]       Run one CBM tool, e.g. tool get_architecture '{}'
  ui                     Print the UI URL (and open it if xdg-open exists)
  shell                  Interactive shell inside the container
  mcp-config             Write mcp-server/configs/.mcp.json (+ root symlink)
  serve-mcp              Speak MCP on stdio, starting the container if needed
  tokens [--all]         Where this project's context went: model totals, and
                         graph queries vs file reading
  metrics <sub>          Token monitoring: OTLP collector + Prometheus
                         up | down [--volumes] | status | logs [-f] | env
                         | tokens | query EXPR | open

Checks
  verify                 Prove egress is blocked, UI reachable, MCP responding
  harden                 Print the sudo iptables rules for a hard egress DROP

  help                   This text
EOF
}

# ── Preconditions ───────────────────────────────────────────────

require_docker() {
    command -v docker >/dev/null 2>&1 \
        || die "docker is not installed or not on PATH" "$ex_unavailable"
    docker info >/dev/null 2>&1 \
        || die "cannot talk to the docker daemon (is it running, are you in the docker group?)" \
               "$ex_unavailable"
    docker compose version >/dev/null 2>&1 \
        || die "the docker compose plugin is required" "$ex_unavailable"
}

require_source() {
    [[ -f "${cbm_source_dir}/Makefile.cbm" ]] \
        || die "codebase-memory-mcp checkout not found at ${cbm_source_dir}
       run: git submodule update --init 3rdparty/codebase-memory-mcp" "$ex_unavailable"
}

container_is_running() {
    [[ "$(docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null)" == "true" ]]
}

require_running() {
    container_is_running || die "container '${container_name}' is not running — ./cbm.sh up" \
                                "$ex_unavailable"
}

# Compose needs these for the same-path mount and the uid match; write them to
# .env as well so a bare `docker compose` in this directory behaves identically.
write_env_file() {
    # Keep the existing secret; never source .env as executable shell code.
    local ui_password
    ui_password="$(python3 - "$env_file" <<'PYENV'
import pathlib, secrets, sys
path = pathlib.Path(sys.argv[1])
values = path.read_text().splitlines() if path.exists() else []
password = next((line.split("=", 1)[1] for line in values
                 if line.startswith("CBM_UI_PASSWORD=")), "")
if not password:
    password = secrets.token_hex(24)
if not password.isascii() or not (16 <= len(password) <= 128) or not all(c.isalnum() or c in "_-" for c in password):
    sys.exit("CBM_UI_PASSWORD must be 16-128 letters, digits, underscores or hyphens")
print(password)
PYENV
)" || die "cannot prepare UI password"
    chmod 600 "$env_file" 2>/dev/null || true
    (umask 077; cat > "$env_file" <<EOF
# Generated by cbm.sh; CBM_UI_PASSWORD is preserved across runs.
CBM_WORKSPACE=${workspace_dir}
CBM_UID=$(id -u)
CBM_GID=$(id -g)
CBM_UI_PORT=${ui_port}
CBM_CONTAINER=${container_name}
CBM_UI_PASSWORD=${ui_password}
CBM_PROM_PORT=${prom_port}
CBM_OTLP_GRPC_PORT=${otlp_grpc_port}
CBM_OTLP_HTTP_PORT=${otlp_http_port}
EOF
    )
}

compose() {
    write_env_file
    CBM_WORKSPACE="$workspace_dir" \
    CBM_UID="$(id -u)" \
    CBM_GID="$(id -g)" \
    CBM_UI_PORT="$ui_port" \
    CBM_CONTAINER="$container_name" \
    docker compose --file "$compose_file" "$@"
}

# The metrics services sit behind a compose profile, so every plain `compose`
# call above ignores them and every metrics call has to ask for them by name.
compose_metrics() {
    compose --profile metrics "$@"
}

# One-shot CBM command inside the running container.
cbm_exec() {
    docker exec "$container_name" codebase-memory-mcp "$@"
}

# ── Commands ────────────────────────────────────────────────────

cmd_build() {
    local no_cache=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-cache) no_cache="--no-cache" ;;
            *) die "build: unknown option '$1'" "$ex_usage" ;;
        esac
        shift
    done
    require_docker
    require_source
    log "building ${CBM_IMAGE:-cbm-server:local} (first build compiles 162 grammars — minutes)"
    compose build ${no_cache:+"$no_cache"}
    log "built"
}

cmd_up() {
    require_docker
    require_source
    log "starting ${container_name} (workspace mounted read-only at ${workspace_dir})"
    compose up --detach
    wait_for_ui || warn "UI did not answer yet — check ./cbm.sh logs"
    cmd_status
}

cmd_down() {
    local with_volumes=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --volumes|-v) with_volumes="--volumes" ;;
            *) die "down: unknown option '$1'" "$ex_usage" ;;
        esac
        shift
    done
    require_docker
    [[ -n "$with_volumes" ]] && warn "dropping the index cache volume — the next start re-indexes"
    compose down ${with_volumes:+"$with_volumes"}
}

cmd_restart() {
    require_docker
    compose up --detach --force-recreate
    wait_for_ui || warn "UI did not answer yet — check ./cbm.sh logs"
}

wait_for_ui() {
    local attempt
    for (( attempt = 0; attempt < 30; attempt++ )); do
        if (exec 3<>"/dev/tcp/127.0.0.1/${ui_port}") 2>/dev/null; then
            return 0
        fi
        sleep 1
    done
    return 1
}

cmd_status() {
    require_docker
    compose ps
    if container_is_running; then
        local health
        health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
                  "$container_name" 2>/dev/null || echo unknown)"
        printf '  health : %s\n' "$health"
        printf '  UI     : http://localhost:%s' "$ui_port"
        if (exec 3<>"/dev/tcp/127.0.0.1/${ui_port}") 2>/dev/null; then
            printf '  (reachable)\n'
        else
            printf '  (not answering)\n'
        fi
        printf '  MCP    : docker exec -i %s codebase-memory-mcp\n' "$container_name"
        printf '  roots  :\n'
        cbm_exec allow-root --list 2>/dev/null | sed 's/^/           /' || true
    fi
}

cmd_logs() {
    require_docker
    local follow=""
    [[ "${1:-}" == "-f" || "${1:-}" == "--follow" ]] && follow="--follow"
    compose logs --tail 200 ${follow:+"$follow"}
}

cmd_shell() {
    require_running
    docker exec -it "$container_name" bash
}

# CBM's project model is one graph per repository, and a repo's registered
# submodules are skipped in the parent index (they are their own projects).
# A workspace of submodules therefore indexes as: the root, then each project.
#
# ${vendor_dir} is not itself a repo — it is a directory OF repos — so it is
# descended into rather than indexed, giving each vendored upstream its own
# graph exactly like a first-party project.
discover_repos() {
    local entry nested
    for entry in "$workspace_dir"/*/; do
        entry="${entry%/}"
        if [[ "$(basename -- "$entry")" == "$vendor_dir" ]]; then
            for nested in "$entry"/*/; do
                nested="${nested%/}"
                [[ -e "${nested}/.git" ]] || continue
                printf '%s\n' "$nested"
            done
            continue
        fi
        [[ -e "${entry}/.git" ]] || continue
        printf '%s\n' "$entry"
    done
}

index_one() {
    local target="$1"
    log "indexing ${target}"
    cbm_exec cli --quiet index_repository --repo-path "$target" \
        | tail -1 \
        | python3 -c '
import json, sys

raw = sys.stdin.read().strip()
try:
    result = json.loads(raw)
except json.JSONDecodeError:
    print(raw)
    sys.exit(0)
print("     {project}: {nodes} nodes, {edges} edges ({status})".format(
    project=result.get("project", "?"),
    nodes=result.get("nodes", "?"),
    edges=result.get("edges", "?"),
    status=result.get("status", "?")))
'
}

cmd_index() {
    local target="${1:-}"
    require_running

    # One grant covers the whole tree; indexing is confined to it afterwards.
    log "granting indexing root ${workspace_dir}"
    cbm_exec allow-root "$workspace_dir" >/dev/null

    if [[ -n "$target" ]]; then
        target="$(cd -- "$target" 2>/dev/null && pwd)" \
            || die "index: not a directory: ${1}" "$ex_usage"
        [[ "$target" == "$workspace_dir" || "$target" == "$workspace_dir"/* ]] \
            || die "index: ${target} is outside the mounted workspace (${workspace_dir})" "$ex_usage"
        index_one "$target"
        return
    fi

    index_one "$workspace_dir"
    local repo
    while IFS= read -r repo; do
        index_one "$repo"
    done < <(discover_repos)
}

cmd_tool() {
    local name="${1:-}"
    [[ -n "$name" ]] || die "tool: a tool name is required, e.g. tool get_architecture '{}'" "$ex_usage"
    shift
    local args="${1:-}"
    [[ -n "$args" ]] || args='{}'
    require_running
    # Piped stdin is the supported way to pass JSON args; a positional JSON
    # blob is deprecated upstream.
    printf '%s' "$args" | docker exec -i "$container_name" codebase-memory-mcp cli "$name"
}

cmd_ui() {
    printf 'http://localhost:%s\n' "$ui_port"
    command -v xdg-open >/dev/null 2>&1 && xdg-open "http://localhost:${ui_port}" >/dev/null 2>&1 &
    return 0
}

# Claude Code only auto-discovers .mcp.json at the PROJECT ROOT. Keep the
# canonical file with the rest of the MCP wiring and point a root symlink at
# it, so the file lives where you filed it and discovery still works.
cmd_mcp_config() {
    local canonical="${workspace_dir}/mcp-server/configs/.mcp.json"
    local root_link="${workspace_dir}/.mcp.json"

    mkdir -p -- "$(dirname -- "$canonical")"
    python3 - "$canonical" "$mcp_server_name" "${script_dir}/cbm.sh" <<'PYEOF'
import json, pathlib, sys

path, name, launcher = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
config = {}
if path.exists():
    try:
        config = json.loads(path.read_text() or "{}")
    except json.JSONDecodeError as exc:
        sys.exit(f"error: {path} is not valid JSON ({exc}) - fix or remove it first")

servers = config.setdefault("mcpServers", {})
servers[name] = {
    "command": launcher,
    "args": ["serve-mcp"],
}
path.write_text(json.dumps(config, indent=2) + "\n")
print(f"registered MCP server '{name}' in {path}")
PYEOF

    local relative="${canonical#"${workspace_dir}"/}"
    if [[ -e "$root_link" && ! -L "$root_link" ]]; then
        warn "${root_link} is a real file, not a link - leaving it alone; merge it by hand"
    else
        ln -sfn -- "$relative" "$root_link"
        log "linked .mcp.json -> ${relative} (the root is where Claude Code looks)"
    fi
    log "restart Claude Code (or /mcp reconnect) to pick the server up"
}

# The .mcp.json entry points here rather than straight at `docker exec`, so an
# agent session brings the container up by itself if it is not running (after a
# `./cbm.sh down`, say). stdout is the JSON-RPC channel — every diagnostic here
# goes to stderr, which the client records in its MCP server log.
cmd_serve_mcp() {
    require_docker
    if ! container_is_running; then
        log "container '${container_name}' is not running — starting it"
        compose up --detach >/dev/null \
            || die "could not start the container; run ./cbm.sh up for the full output" \
                   "$ex_unavailable"
    fi
    exec docker exec -i "$container_name" codebase-memory-mcp
}

# Where the context went. Model totals come from the transcripts' own usage
# counters (exact); the per-tool split is estimated from payload size, because
# the API never attributes tokens to an individual tool call.
cmd_tokens() {
    local sessions=1
    local top=10
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)      sessions=0 ;;
            --sessions) shift; sessions="${1:-}" ;;
            --top)      shift; top="${1:-}" ;;
            *) die "tokens: unknown option '$1'" "$ex_usage" ;;
        esac
        shift
    done
    [[ "$sessions" =~ ^[0-9]+$ ]] || die "tokens: --sessions takes a number" "$ex_usage"
    [[ "$top" =~ ^[0-9]+$ ]] || die "tokens: --top takes a number" "$ex_usage"

    [[ -f "${script_dir}/token-report.py" ]] \
        || die "token-report.py is not in this tree (removed in c8a8b2c).
       For exact per-tool attribution use the metrics stack instead:
         ./cbm.sh metrics up && ./cbm.sh metrics env
         ./cbm.sh metrics tokens" "$ex_unavailable"

    python3 "${script_dir}/token-report.py" \
        --workspace "$workspace_dir" --sessions "$sessions" --top "$top"
}

# ── Token monitoring ────────────────────────────────────────────
#
# Claude Code exports OpenTelemetry metrics that DO attribute tokens to an
# individual MCP server and tool — which the transcript estimate never could.
# Sessions are short-lived and push over OTLP; the collector holds the counters
# and Prometheus scrapes it.

metrics_usage() {
    cat <<EOF
Usage: ./cbm.sh metrics <subcommand>

  up                     Start the collector and Prometheus
  down [--volumes]       Stop them; --volumes also drops the metric history
  status                 Containers, endpoints, scrape targets, series count
  logs [-f]              Collector + Prometheus logs
  env [--export]         The OTEL_* settings Claude Code needs
  tokens                 Token totals by kind, model, MCP server and MCP tool
  query EXPR             One instant PromQL query
  open                   Print (and open) http://localhost:${prom_port}
EOF
}

require_curl() {
    command -v curl >/dev/null 2>&1 \
        || die "curl is required for this subcommand" "$ex_unavailable"
}

prom_is_up() {
    (exec 3<>"/dev/tcp/127.0.0.1/${prom_port}") 2>/dev/null
}

# One instant PromQL query; prints the raw JSON on stdout.
prom_query() {
    local expr="$1"
    require_curl
    curl -sS -G --max-time 10 \
        --data-urlencode "query=${expr}" \
        "http://127.0.0.1:${prom_port}/api/v1/query"
}

# Render an instant vector as "<label>  <value>  <share>" rows.
prom_table() {
    local expr="$1" label="$2"
    prom_query "$expr" | python3 -c '
import json, sys

label = sys.argv[1]
try:
    doc = json.load(sys.stdin)
except json.JSONDecodeError:
    print("     prometheus returned no JSON - is it running?")
    raise SystemExit
if doc.get("status") != "success":
    print("     query failed: %s" % doc.get("error", "?"))
    raise SystemExit

rows = [(r["metric"].get(label) or "(unattributed)", float(r["value"][1]))
        for r in doc.get("data", {}).get("result", [])]
if not rows:
    print("     (no data yet)")
    raise SystemExit

rows.sort(key=lambda kv: -kv[1])
total = sum(value for _, value in rows) or 1.0
width = max(len(name) for name, _ in rows)
for name, value in rows:
    print("     %-*s  %14s  %5.1f%%"
          % (width, name, format(int(value), ","), 100.0 * value / total))
' "$label"
}

cmd_metrics() {
    local sub="${1:-status}"
    [[ $# -gt 0 ]] && shift
    case "$sub" in
        up)      metrics_up "$@" ;;
        down)    metrics_down "$@" ;;
        status)  metrics_status "$@" ;;
        logs)    metrics_logs "$@" ;;
        env)     metrics_env "$@" ;;
        tokens)  metrics_tokens "$@" ;;
        query)   metrics_query "$@" ;;
        open)    metrics_open "$@" ;;
        help|-h|--help) metrics_usage ;;
        *)       metrics_usage; die "metrics: unknown subcommand '${sub}'" "$ex_usage" ;;
    esac
}

metrics_up() {
    require_docker
    log "starting the OTLP collector and Prometheus"
    compose_metrics up --detach otelcol prometheus
    wait_for_prometheus || warn "Prometheus did not answer yet — ./cbm.sh metrics logs"
    metrics_status
    printf '\n'
    log "Claude Code still has to be told to export — ./cbm.sh metrics env"
}

metrics_down() {
    local with_volumes=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --volumes|-v) with_volumes="--volumes" ;;
            *) die "metrics down: unknown option '$1'" "$ex_usage" ;;
        esac
        shift
    done
    require_docker
    if [[ -n "$with_volumes" ]]; then
        warn "dropping the Prometheus data volume — the metric history goes with it"
        compose_metrics rm --stop --force --volumes otelcol prometheus
        docker volume rm -- "${CBM_PROM_VOLUME:-cbm-prometheus-data}" >/dev/null 2>&1 || true
    else
        compose_metrics stop otelcol prometheus
        compose_metrics rm --force otelcol prometheus
    fi
}

wait_for_prometheus() {
    local attempt
    for (( attempt = 0; attempt < 30; attempt++ )); do
        prom_is_up && return 0
        sleep 1
    done
    return 1
}

metrics_status() {
    require_docker
    compose_metrics ps otelcol prometheus
    printf '  OTLP   : http://localhost:%s (grpc) · http://localhost:%s (http)\n' \
        "$otlp_grpc_port" "$otlp_http_port"
    printf '  Prom   : http://localhost:%s' "$prom_port"
    if prom_is_up; then
        printf '  (reachable)\n'
    else
        printf '  (not answering)\n'
        return 0
    fi

    printf '  targets:\n'
    require_curl
    curl -sS --max-time 10 "http://127.0.0.1:${prom_port}/api/v1/targets?state=any" \
        | python3 -c '
import json, sys

doc = json.load(sys.stdin)
for target in doc.get("data", {}).get("activeTargets", []):
    labels = target.get("labels", {})
    print("           %-12s %-22s %s%s" % (
        labels.get("job", "?"),
        labels.get("instance", "?"),
        target.get("health", "?"),
        (" — " + target["lastError"]) if target.get("lastError") else ""))
' || true

    printf '  series : '
    prom_query 'count({__name__=~"claude_code.*"})' | python3 -c '
import json, sys

result = json.load(sys.stdin).get("data", {}).get("result", [])
if result:
    print("%s claude_code series stored" % result[0]["value"][1])
else:
    print("no claude_code series yet — is telemetry exported? ./cbm.sh metrics env")
' || printf '?\n'
}

metrics_logs() {
    require_docker
    local follow=""
    [[ "${1:-}" == "-f" || "${1:-}" == "--follow" ]] && follow="--follow"
    compose_metrics logs --tail 100 ${follow:+"$follow"} otelcol prometheus
}

# Claude Code reads these from its own environment; without them nothing is
# exported and Prometheus stays empty.
metrics_env() {
    local as_export=""
    [[ "${1:-}" == "--export" ]] && as_export=1

    local -a settings=(
        "CLAUDE_CODE_ENABLE_TELEMETRY=1"
        "OTEL_METRICS_EXPORTER=otlp"
        "OTEL_EXPORTER_OTLP_PROTOCOL=grpc"
        "OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:${otlp_grpc_port}"
        # Without this a user-configured MCP server is redacted to "custom",
        # which loses exactly the attribution this stack exists for.
        "OTEL_LOG_TOOL_DETAILS=1"
        # Default is 60s; a session shorter than that would export nothing.
        "OTEL_METRIC_EXPORT_INTERVAL=10000"
    )

    local setting
    if [[ -n "$as_export" ]]; then
        for setting in "${settings[@]}"; do
            printf 'export %s\n' "$setting"
        done
        return
    fi

    cat <<EOF
Claude Code exports only when these are set in its environment:

EOF
    for setting in "${settings[@]}"; do
        printf '  export %s\n' "$setting"
    done
    cat <<EOF

For this shell:            eval "\$(./cbm.sh metrics env --export)"
For every session here:    put them in .claude/settings.json under "env"
                           (they apply to the session Claude Code starts, so
                            restart it afterwards)
EOF
}

metrics_query() {
    local expr="${1:-}"
    [[ -n "$expr" ]] || die "metrics query: a PromQL expression is required" "$ex_usage"
    prom_query "$expr" | python3 -m json.tool
}

# The four cuts worth having: what kind of token, which model, which MCP
# server, which MCP tool.
metrics_tokens() {
    prom_is_up || die "Prometheus is not running — ./cbm.sh metrics up" "$ex_unavailable"
    local metric='claude_code_token_usage_tokens_total'

    log "tokens by kind"
    prom_table "sum by (type) (${metric})" type

    log "tokens by model"
    prom_table "sum by (model) (${metric})" model

    log "tokens by MCP server"
    prom_table "sum by (mcp_server_name) (${metric})" mcp_server_name

    log "tokens by MCP tool"
    prom_table "topk(15, sum by (mcp_tool_name) (${metric}))" mcp_tool_name
}

metrics_open() {
    printf 'http://localhost:%s\n' "$prom_port"
    command -v xdg-open >/dev/null 2>&1 && xdg-open "http://localhost:${prom_port}" >/dev/null 2>&1 &
    return 0
}

# Three independent claims, each checked rather than asserted.
cmd_verify() {
    require_running
    local failures=0

    log "1/4 egress — TCP to a public address must not connect"
    if docker exec "$container_name" \
        timeout 8 socat -T3 - TCP:1.1.1.1:443 </dev/null >/dev/null 2>&1; then
        warn "FAIL: the container reached 1.1.1.1:443"
        failures=$((failures + 1))
    else
        log "     ok — no route out"
    fi

    log "2/4 dns — name resolution must fail"
    if docker exec "$container_name" getent hosts github.com >/dev/null 2>&1; then
        warn "FAIL: github.com resolved inside the container"
        failures=$((failures + 1))
    else
        log "     ok — resolver is black-holed"
    fi

    log "3/4 ui — http://localhost:${ui_port} must answer on the host"
    if command -v curl >/dev/null 2>&1; then
        local code
        code="$(curl -sS -m 5 -o /dev/null -w '%{http_code}' "http://localhost:${ui_port}/" || echo 000)"
        if [[ "$code" == "401" ]]; then
            log "     ok — HTTP 401 (authentication required)"
        else
            warn "FAIL: HTTP ${code}"
            failures=$((failures + 1))
        fi
    elif (exec 3<>"/dev/tcp/127.0.0.1/${ui_port}") 2>/dev/null; then
        log "     ok — port accepting (install curl for a full check)"
    else
        warn "FAIL: nothing listening on 127.0.0.1:${ui_port}"
        failures=$((failures + 1))
    fi

    log "4/4 mcp — stdio handshake over docker exec"
    local handshake
    handshake="$(printf '%s\n' \
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"cbm.sh","version":"1"}}}' \
        | timeout 30 docker exec -i "$container_name" codebase-memory-mcp 2>/dev/null \
        | head -1)"
    if [[ "$handshake" == *'"result"'* ]]; then
        log "     ok — server initialized"
    else
        warn "FAIL: no initialize result (got: ${handshake:-<empty>})"
        failures=$((failures + 1))
    fi

    if (( failures > 0 )); then
        die "${failures} check(s) failed" "$ex_software"
    fi
    log "all checks passed"
}

# Masquerade-off already denies egress. These rules make it an explicit DROP,
# which also covers hosts on your LAN that could route back to the bridge.
cmd_harden() {
    local subnet="${CBM_SUBNET:-172.31.99.0/24}"
    cat <<EOF
Optional hard block (needs sudo; masquerade is already off without it).
Adds an explicit DROP for anything leaving ${subnet} for a non-private address:

  sudo iptables -I DOCKER-USER -s ${subnet} ! -d 10.0.0.0/8 \\
      ! -d 172.16.0.0/12 ! -d 192.168.0.0/16 -j DROP
  sudo iptables -I DOCKER-USER -d ${subnet} ! -s 10.0.0.0/8 \\
      ! -s 172.16.0.0/12 ! -s 192.168.0.0/16 -j DROP

Persist with iptables-persistent, or re-run after a reboot. Remove with the
same commands using -D instead of -I. Re-check with: ./cbm.sh verify
EOF
}

main() {
    local command="${1:-help}"
    [[ $# -gt 0 ]] && shift
    case "$command" in
        build)       cmd_build "$@" ;;
        up)          cmd_up "$@" ;;
        down)        cmd_down "$@" ;;
        restart)     cmd_restart "$@" ;;
        status)      cmd_status "$@" ;;
        logs)        cmd_logs "$@" ;;
        shell)       cmd_shell "$@" ;;
        index)       cmd_index "$@" ;;
        tool)        cmd_tool "$@" ;;
        ui)          cmd_ui "$@" ;;
        mcp-config)  cmd_mcp_config "$@" ;;
        serve-mcp)   cmd_serve_mcp "$@" ;;
        tokens)      cmd_tokens "$@" ;;
        metrics)     cmd_metrics "$@" ;;
        verify)      cmd_verify "$@" ;;
        harden)      cmd_harden "$@" ;;
        help|-h|--help) usage ;;
        *)           usage; die "unknown command '${command}'" "$ex_usage" ;;
    esac
}

main "$@"
