#!/usr/bin/env bash
#
# cbm-entrypoint.sh — PID 1 payload for the codebase-memory-mcp container.
#
# Keeps one long-lived CBM session alive. That session owns the shared
# coordination daemon, which in turn owns the graph UI; every `docker exec`
# MCP session started by an agent joins the same daemon and cache root.

set -euo pipefail

readonly ui_port="${CBM_UI_PORT:-9749}"
forwarder_pid=""

log() {
    printf '[cbm-entrypoint] %s\n' "$*" >&2
}

cleanup() {
    if [[ -n "$forwarder_pid" ]]; then
        kill "$forwarder_pid" 2>/dev/null || true
    fi
}

validate_env() {
    if [[ ! "$ui_port" =~ ^[0-9]+$ ]] || (( ui_port < 1 || ui_port > 65535 )); then
        log "CBM_UI_PORT must be a port number, got '${ui_port}'"
        exit 64
    fi
    if ! command -v codebase-memory-mcp >/dev/null 2>&1; then
        log "codebase-memory-mcp is not on PATH"
        exit 127
    fi
}

# The UI listener binds 127.0.0.1 only (src/ui/httpd.c) and rejects any Host
# header that is not 127.0.0.1:<port> or localhost:<port> — a deliberate
# anti-DNS-rebinding control. Docker's published port DNATs to the container's
# bridge address instead, which that listener never sees. Forward bridge:<port>
# to loopback:<port>, same port on both sides, so the browser's
# `Host: localhost:<port>` still validates.
start_ui_forwarder() {
    local bridge_ip
    bridge_ip="$(ip -4 -o addr show scope global 2>/dev/null \
        | awk 'NR == 1 { split($4, cidr, "/"); print cidr[1] }')"

    if [[ -z "$bridge_ip" ]]; then
        log "no global IPv4 address — UI stays reachable inside the container only"
        return 0
    fi

    socat "TCP-LISTEN:${ui_port},bind=${bridge_ip},fork,reuseaddr" \
          "TCP:127.0.0.1:${ui_port}" &
    forwarder_pid=$!
    log "UI forwarder ${bridge_ip}:${ui_port} -> 127.0.0.1:${ui_port} (pid ${forwarder_pid})"
}

main() {
    validate_env
    trap cleanup EXIT
    start_ui_forwarder

    log "starting codebase-memory-mcp (ui=true port=${ui_port} cache=${CBM_CACHE_DIR:-default})"
    # Launched outside an MCP client the server exits as soon as stdin closes
    # (documented upstream behaviour), so hold stdin open for the life of the
    # container. This session never speaks MCP; agents attach via `docker exec`.
    exec codebase-memory-mcp --ui=true "--port=${ui_port}" < <(exec sleep infinity)
}

main "$@"
