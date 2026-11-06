#!/usr/bin/env bash
#
# kb.sh — read and search the Confluence mirror in .db/confluence.db.
#
# page, status and search --keyword run kb/kb.py on the host (Python standard
# library only). index and search need the embedding model, so they go to the
# confluence search service of docker/confluence/ (container
# jo-confluence-kb), which keeps the model loaded. The first search starts it
# through docker/confluence/services.sh; started that way it stops itself after
# 30 minutes without a request, which frees its memory (`services.sh up` keeps
# it up instead). If it cannot start, a one-off container does the work
# (slower: it loads the model each time).
# Nothing here talks to Confluence; sync.sh fills the database.
#
# Usage: ./kb.sh <command> [options]   ( ./kb.sh help )

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
readonly kb_py="${script_dir}/kb/kb.py"
readonly services="${script_dir}/../docker/confluence/services.sh"   # this mirror's own compose project
readonly db_dir="${script_dir}/.db"
readonly image="jo-confluence-kb:local"
readonly container="jo-confluence-kb"
readonly idle_seconds=1800
export KB_DB="${db_dir}/confluence.db"

# Exit codes: 64 usage, 69 unavailable (docker/image), 75 no server, 78 config.
readonly ex_usage=64
readonly ex_unavailable=69
readonly ex_no_server=75
readonly ex_config=78

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit "${2:-1}"; }

usage() {
    cat <<EOF
Usage: ./kb.sh <command> [options]

  search <question> [--limit N] [--keyword]
                   Keyword and meaning matches, fused; --keyword skips the
                   model (and Docker)
  page <id> [--source]
                   A page as text with its comments; --source prints the
                   storage-format XHTML as served
  status           Pages, indexed / not indexed, chunks, newest timestamps,
                   and the search container's state and memory
  index [--all]    Embed the pages whose indexed flag is 0 (--all: every page)
  up               Start the search service now (search starts it anyway;
                   started from here it stops after ${idle_seconds}s idle)
  down             Stop it and free its memory
  build            Build the ${image} image (model + runtime; network at build only)
  help             This text

Database: ${KB_DB}
EOF
}

host_kb() {
    command -v python3 >/dev/null 2>&1 || die "python3 is required" "$ex_unavailable"
    [[ -f "$KB_DB" ]] || die "no database yet: run ${script_dir}/sync.sh pull" "$ex_config"
    python3 "$kb_py" "$@"
}

have_image() {
    command -v docker >/dev/null 2>&1 && docker image inspect "$image" >/dev/null 2>&1
}

server_running() {
    [[ "$(docker inspect --format '{{.State.Running}}' "$container" 2>/dev/null)" == true ]]
}

server_ready() {
    "$services" exec ping >/dev/null 2>&1
}

# Start the service unless it answers already; services.sh waits for health.
server_up() {
    [[ -f "$KB_DB" ]] || die "no database yet: run ${script_dir}/sync.sh pull" "$ex_config"
    have_image || die "no ${image} image: run ${script_dir}/kb.sh build" "$ex_unavailable"
    server_ready && return 0
    "$services" up --idle "$idle_seconds"
}

# Run a model command on the service; a one-off container if it cannot be
# started or went away mid-way.
container_kb() {
    [[ -f "$KB_DB" ]] || die "no database yet: run ${script_dir}/sync.sh pull" "$ex_config"
    have_image || die "no ${image} image: run ${script_dir}/kb.sh build" "$ex_unavailable"
    local code=0
    if ( server_up ); then
        "$services" exec "$@" || code=$?
        (( code == ex_no_server )) || return "$code"
        warn "${container} went away; running this once in a one-off container"
    else
        warn "${container} could not start; running this once in a one-off container"
    fi
    "$services" run "$@"
}

cmd_status() {
    host_kb status
    if server_running; then
        printf 'container  %s up, %s\n' "$container" \
            "$(docker stats --no-stream --format '{{.MemUsage}}' "$container")"
    else
        printf 'container  %s not running (the next search starts it)\n' "$container"
    fi
}

cmd_search() {
    local arg keyword=false
    for arg in "$@"; do
        [[ "$arg" == --keyword ]] && keyword=true
    done
    (( $# > 0 )) || die "search: give a question" "$ex_usage"
    if [[ "$keyword" == true ]]; then
        host_kb search "$@"
    elif have_image; then
        container_kb search "$@"
    else
        warn "no ${image} image, so keyword matches only — run ${script_dir}/kb.sh build for meaning matches"
        host_kb search "$@" --keyword
    fi
}

main() {
    local command="${1:-help}"
    (( $# > 0 )) && shift
    case "$command" in
        search) cmd_search "$@" ;;
        page)   (( $# > 0 )) || die "page: give a page id" "$ex_usage"; host_kb page "$@" ;;
        status) cmd_status ;;
        index)  container_kb index "$@" ;;
        up)     server_up ;;
        down)   "$services" down ;;
        build)  "$services" build ;;
        help|-h|--help) usage ;;
        *) usage >&2; exit "$ex_usage" ;;
    esac
}

main "$@"
