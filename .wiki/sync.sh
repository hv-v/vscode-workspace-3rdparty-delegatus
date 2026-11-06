#!/usr/bin/env bash
#
# sync.sh — keep a local, read-only mirror of MediaWiki pages that kb.sh can
# search and the codebase-memory graph can index.
#
# What lands on disk is the wiki's own source, not a re-rendering:
#   .db/wiki.db           pages as wikitext, with revid, updated_at and the
#                         indexed flag; read and searched with kb.sh
#   navigation_map.md     the index — read it first
#
# Read-only by construction, twice over:
#   - the login is a bot password (Special:BotPasswords) granted only basic
#     rights, so the server itself refuses any write;
#   - api_login sends the one POST (action=login, which MediaWiki accepts no
#     other way); every other request is a GET from api_get. No redirects,
#     https only, and only to base_url, whose host must end in
#     allowed_host_suffix. Credentials reach curl through a pipe, never argv,
#     and the session cookie lives in a mode-600 temp file deleted on exit.
#
# Runs on the macOS system bash (3.2): no associative arrays, no mapfile.
#
# Usage: ./sync.sh <command> [options]   ( ./sync.sh help )

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
workspace_dir="$(cd -- "${script_dir}/.." && pwd)"
readonly workspace_dir
readonly sources_file="${script_dir}/sources.json"
readonly kb_py="${script_dir}/kb/kb.py"
readonly kb_script="${script_dir}/kb.sh"
export KB_DB="${script_dir}/.db/wiki.db"
readonly nav_file="${script_dir}/navigation_map.md"
readonly cbm_script="${workspace_dir}/docker/cbm/cbm.sh"

readonly credentials_file="${IPP_WIKI_CONFIG:-${script_dir}/.ipp-wiki.env}"   # git- and cbm-ignored
readonly launchd_label="cz.ipp.wiki-sync"
readonly launchd_plist="${HOME}/Library/LaunchAgents/${launchd_label}.plist"
readonly unit_name="ipp-wiki-sync"
readonly unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

readonly batch=50   # MediaWiki's limit for titles / pageids per request

# Exit codes: 64 usage, 65 bad data, 69 unavailable (network/server), 70 internal, 78 config.
readonly ex_usage=64
readonly ex_dataerr=65
readonly ex_unavailable=69
readonly ex_software=70
readonly ex_config=78

base_url=""
api_url=""
pin=""
wiki_user=""
wiki_pass=""
cookie_jar=""
curl_err=""
namespaces_file=""
fetched_at=""
max_pages=100
changed=()
tmp_paths=()

cleanup() {
    local path
    for path in ${tmp_paths[@]+"${tmp_paths[@]}"}; do
        rm -rf -- "$path"
    done
}
trap cleanup EXIT

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit "${2:-$ex_software}"; }

new_tmp() {
    local path
    path="$(mktemp "${TMPDIR:-/tmp}/ipp-wiki.XXXXXX")"   # mode 600
    tmp_paths+=("$path")
    printf '%s' "$path"
}

usage() {
    cat <<EOF
Usage: ./sync.sh <command> [options]

  check               Log in, print who you are and what the login may do
  pull [--index]      Refresh everything in sources.json; only pages whose
                      revision moved are downloaded. --index also embeds the
                      changed pages (kb.sh index) and re-indexes the graph.
  add <what>          Add to sources.json, then pull --index. <what> is a page
                      link or title, a Category:<name> (link or title), or
                      ns:<number> for a whole namespace
  schedule | unschedule
                      Install / remove the weekly refresh, Mondays 09:00
                      (launchd on macOS, a systemd user timer on Linux)
  help                This text

Credentials: ${credentials_file}
  WIKI_USER=<user>@<bot name> and WIKI_PASS=<bot password>, mode 600
  (create the bot password at Special:BotPasswords with only basic rights)
EOF
}

# ── Configuration ───────────────────────────────────────────────

require_tools() {
    local tool
    for tool in curl jq python3; do
        command -v "$tool" >/dev/null 2>&1 || die "${tool} is required" "$ex_unavailable"
    done
    [[ -f "$sources_file" ]] || die "missing ${sources_file}" "$ex_config"
    jq -e . "$sources_file" >/dev/null 2>&1 || die "${sources_file} is not valid JSON" "$ex_config"
}

# base_url: https, no path, under allowed_host_suffix; pin optional.
load_sources() {
    local suffix api_path host
    suffix="$(jq -r '.allowed_host_suffix // ""' "$sources_file")"
    [[ "$suffix" =~ ^\.[A-Za-z0-9.-]+$ ]] \
        || die "sources.json: allowed_host_suffix must be a domain suffix starting with '.'" "$ex_config"
    base_url="$(jq -r '.base_url // ""' "$sources_file")"
    base_url="${base_url%/}"
    [[ "$base_url" =~ ^https://([A-Za-z0-9.-]+)$ ]] \
        || die "sources.json: base_url must be https://<host> with no path" "$ex_config"
    host="${BASH_REMATCH[1]}"
    [[ "$host" == *"$suffix" ]] || die "refusing ${host}: not under ${suffix}" "$ex_config"
    api_path="$(jq -r '.api_path // "/api.php"' "$sources_file")"
    [[ "$api_path" =~ ^/[A-Za-z0-9._/-]*\.php$ ]] \
        || die "sources.json: api_path must look like /api.php" "$ex_config"
    api_url="${base_url}${api_path}"
    pin="$(jq -r '.pin // ""' "$sources_file")"
    [[ -z "$pin" || "$pin" =~ ^sha256//[A-Za-z0-9+/]{43}=$ ]] \
        || die "sources.json: pin is malformed (sha256//<base64>=), or remove it" "$ex_config"
    max_pages="$(jq -r '.max_pages // 100' "$sources_file")"
    [[ "$max_pages" =~ ^[0-9]+$ ]] || die "sources.json: max_pages must be a number" "$ex_config"
}

file_mode() {
    stat -c '%a' -- "$1" 2>/dev/null || stat -f '%Lp' -- "$1"   # GNU, then BSD/macOS
}

strip_quotes() {
    local value="$1"
    if [[ ${#value} -ge 2 && ( ( "$value" == \"*\" ) || ( "$value" == \'*\' ) ) ]]; then
        value="${value:1:${#value}-2}"
    fi
    printf '%s' "$value"
}

# KEY=VALUE lines, parsed rather than sourced. Errors never echo a value.
load_credentials() {
    [[ -f "$credentials_file" ]] \
        || die "no credentials: copy .ipp-wiki.env.example to ${credentials_file} (mode 600) and fill it in" "$ex_config"
    local mode line key value number=0
    mode="$(file_mode "$credentials_file")"
    [[ "$mode" == 600 || "$mode" == 400 ]] \
        || die "${credentials_file} is mode ${mode}; run: chmod 600 '${credentials_file}'" "$ex_config"
    while IFS= read -r line || [[ -n "$line" ]]; do
        number=$((number + 1))
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        line="${line#export }"
        [[ "$line" == *=* ]] || die "credentials line ${number}: expected KEY=VALUE" "$ex_config"
        key="${line%%=*}"
        key="${key//[[:space:]]/}"
        value="$(strip_quotes "${line#*=}")"
        case "$key" in
            WIKI_USER) wiki_user="$value" ;;
            WIKI_PASS) wiki_pass="$value" ;;
            *) die "credentials line ${number}: unknown key '${key}'" "$ex_config" ;;
        esac
    done < "$credentials_file"
    [[ -n "$wiki_user" && -n "$wiki_pass" ]] \
        || die "${credentials_file} needs WIKI_USER and WIKI_PASS" "$ex_config"
    [[ "$wiki_user" == ?*@?* ]] \
        || die "WIKI_USER must be <user>@<bot name>: the wiki signs in through Keycloak, so the API takes only a bot password (Special:BotPasswords)" "$ex_config"
}

# ── The network ─────────────────────────────────────────────────

curl_base() { # output-file — prints nothing; fills the curl_args array
    curl_args=(--silent --show-error
        --proto '=https' --tlsv1.2
        --connect-timeout 15 --max-time 120
        --cookie "$cookie_jar" --cookie-jar "$cookie_jar"
        --header 'Accept: application/json'
        --output "$1" --write-out '%{http_code}')
    if [[ -n "$pin" ]]; then
        curl_args+=(--pinnedpubkey "$pin")
    fi
}

# Map a curl failure or a non-200 status to a message, and stop.
http_fail() { # what status output-file
    case "$2" in
        *"(90)"*|*pinned*) die "the wiki's public key does not match the pin in sources.json — certificate renewed, or not the real server" "$ex_unavailable" ;;
        *"(6)"*|*"resolve host"*) die "cannot resolve ${base_url} — network or VPN down?" "$ex_unavailable" ;;
        *"(60)"*) die "the wiki's certificate does not verify: ${2}" "$ex_unavailable" ;;
        30?) die "${1}: HTTP ${2} — redirected, probably to the SSO login; stopping" "$ex_unavailable" ;;
        [0-9][0-9][0-9]) die "${1}: HTTP ${2}: $(head -c 300 -- "$3" 2>/dev/null)" "$ex_unavailable" ;;
        *) die "${1} failed: ${2}" "$ex_unavailable" ;;
    esac
}

# Stop on an API-level error: the API answers 200 with {"error": …}.
api_check() { # what response-file
    local code
    code="$(jq -r '.error.code // empty' "$2" 2>/dev/null)" || die "${1}: the answer is not JSON: $(head -c 200 -- "$2")" "$ex_dataerr"
    case "$code" in
        "") ;;
        readapidenied) die "${1}: not logged in (readapidenied) — the session was not accepted" "$ex_unavailable" ;;
        *) die "${1}: API error ${code}: $(jq -r '.error.info // ""' "$2")" "$ex_unavailable" ;;
    esac
    if jq -e '.warnings' "$2" >/dev/null; then
        warn "${1}: $(jq -c '.warnings' "$2" | head -c 300)"
    fi
}

# Every read: GET, no body, no redirects, retried on network errors only.
api_get() { # query output-file
    local status
    curl_base "$2"
    status="$(curl "${curl_args[@]}" --request GET --retry 3 --retry-delay 3 \
        "${api_url}?${1}&format=json&formatversion=2" 2>"$curl_err")" \
        || http_fail "GET" "$(cat -- "$curl_err")" "$2"
    [[ "$status" == 200 ]] || http_fail "GET ${1%%&*}" "$status" "$2"
    api_check "GET ${1%%&*}" "$2"
}

# Secrets are URL-encoded through stdin, so they never appear in argv.
uri_stdin() { jq -sRj '@uri'; }   # -j: no trailing newline, which would end up in the value
uri() { printf '%s' "$1" | uri_stdin; }

# The one POST: action=login with the bot password. Never retried — repeated
# failures can throttle the account.
api_login() {
    local out status token
    cookie_jar="$(new_tmp)"
    out="$(new_tmp)"
    api_get "action=query&meta=tokens&type=login" "$out"
    token="$(jq -r '.query.tokens.logintoken // empty' "$out")"
    [[ -n "$token" ]] || die "login: no login token in the answer" "$ex_unavailable"
    curl_base "$out"
    status="$( {
        printf 'action=login&format=json&formatversion=2&lgname='
        printf '%s' "$wiki_user" | uri_stdin
        printf '&lgpassword='
        printf '%s' "$wiki_pass" | uri_stdin
        printf '&lgtoken='
        printf '%s' "$token" | uri_stdin
    } | curl "${curl_args[@]}" --request POST \
            --header 'Content-Type: application/x-www-form-urlencoded' \
            --data-binary @- "$api_url" 2>"$curl_err")" \
        || http_fail "login" "$(cat -- "$curl_err")" "$out"
    [[ "$status" == 200 ]] || http_fail "login" "$status" "$out"
    [[ "$(jq -r '.login.result // ""' "$out")" == Success ]] \
        || die "login failed: $(jq -r '.login.reason // .login.result // .error.info // "no reason given"' "$out") — check the bot password; not retrying" "$ex_unavailable"
    wiki_pass=""
}

prepare() {
    require_tools
    load_sources
    load_credentials
    curl_err="$(new_tmp)"
    api_login
}

kb() { python3 "$kb_py" "$@"; }

# ── Listing: what the mirror should hold ────────────────────────

# Run a generator query to the end, following `continue`; print "pageid revid".
list_pages() { # query
    local out cont=""
    out="$(new_tmp)"
    while :; do
        api_get "${1}&prop=info${cont:+&${cont}}" "$out"
        jq -r '.query.pages[]? | select(.missing | not) | "\(.pageid) \(.lastrevid)"' "$out"
        cont="$(jq -r '.continue // empty | to_entries | map("\(.key)=\(.value | tostring | @uri)") | join("&")' "$out")"
        [[ -n "$cont" ]] || break
    done
}

list_titles() { # title... — at most $batch
    local joined="" title out
    for title in "$@"; do
        joined="${joined:+${joined}|}${title}"
    done
    out="$(new_tmp)"
    api_get "action=query&redirects=1&prop=info&titles=$(uri "$joined")" "$out"
    jq -r '.query.pages[]? | select(.missing) | .title' "$out" | while IFS= read -r title; do
        warn "no page '${title}' on the wiki (sources.json pages)"
    done
    jq -r '.query.pages[]? | select(.missing | not) | "\(.pageid) \(.lastrevid)"' "$out"
}

# Every page sources.json asks for, deduplicated, capped at max_pages.
list_wanted() { # output-file
    local raw ns category title
    local -a titles=()
    raw="$(new_tmp)"
    while IFS= read -r ns; do
        [[ "$ns" =~ ^[0-9]+$ ]] || die "sources.json: namespaces must be numbers, got '${ns}'" "$ex_config"
        log "listing namespace ${ns}"
        list_pages "action=query&generator=allpages&gapnamespace=${ns}&gapfilterredir=nonredirects&gaplimit=max" >> "$raw"
    done < <(jq -r '.namespaces[]? | tostring' "$sources_file")
    while IFS= read -r category; do
        log "listing Category:${category#Category:}"
        list_pages "action=query&generator=categorymembers&gcmtitle=$(uri "Category:${category#Category:}")&gcmtype=page&gcmlimit=max" >> "$raw"
    done < <(jq -r '.categories[]?' "$sources_file")
    while IFS= read -r title; do
        titles+=("$title")
        if (( ${#titles[@]} == batch )); then
            list_titles "${titles[@]}" >> "$raw"
            titles=()
        fi
    done < <(jq -r '.pages[]?' "$sources_file")
    if (( ${#titles[@]} > 0 )); then
        list_titles "${titles[@]}" >> "$raw"
    fi
    sort -u -k1,1n "$raw" > "$1"
    local total
    total="$(wc -l < "$1" | tr -d ' ')"
    if (( total > max_pages )); then
        warn "sources.json selects ${total} pages; keeping the first ${max_pages} by page id (raise max_pages to keep more)"
        head -n "$max_pages" "$1" > "$raw"
        mv -- "$raw" "$1"
    fi
}

# ── Fetching ────────────────────────────────────────────────────

fetch_ids() { # id... — at most $batch; prints the ids whose content changed
    local joined="" id out
    for id in "$@"; do
        joined="${joined:+${joined}|}${id}"
    done
    out="$(new_tmp)"
    api_get "action=query&pageids=$(uri "$joined")&prop=revisions|info|categories&rvprop=ids|timestamp|user|content&rvslots=main&inprop=url&cllimit=max&clshow=!hidden" "$out"
    kb put-pages "$out" --namespaces "$namespaces_file"
}

# Download every page whose revid moved; a page the batch answer left out
# (the API trims big answers) is asked for again on its own.
pull_pages() { # wanted-file changed-ids-file
    local todo id n=0
    local -a ids=()
    todo="$(new_tmp)"
    kb plan < "$1" > "$todo"
    log "$(wc -l < "$todo" | tr -d ' ') of $(wc -l < "$1" | tr -d ' ') page(s) to download"
    while IFS= read -r id; do
        ids+=("$id")
        if (( ${#ids[@]} == batch )); then
            fetch_ids "${ids[@]}" >> "$2"
            n=$((n + ${#ids[@]}))
            log "fetched ${n}"
            ids=()
        fi
    done < "$todo"
    if (( ${#ids[@]} > 0 )); then
        fetch_ids "${ids[@]}" >> "$2"
    fi
    kb plan < "$1" > "$todo"
    while IFS= read -r id; do
        fetch_ids "$id" >> "$2"
    done < "$todo"
    kb plan < "$1" > "$todo"
    if [[ -s "$todo" ]]; then
        warn "$(wc -l < "$todo" | tr -d ' ') page(s) could not be fetched (hidden revision or too large): $(tr '\n' ' ' < "$todo")"
    fi
}

write_navigation_map() { # changed-ids-file
    {
        printf '# Wiki navigation map\n\n'
        printf '> Generated by `sync.sh` from %s — last pull %s. Read this first.\n' "$base_url" "$fetched_at"
        printf '> ★ = changed in the last pull. Pages are the wiki'"'"'s own wikitext, in the database.\n\n'
        if [[ -f "$KB_DB" ]]; then
            kb nav-map < "$1"
        else
            printf '_Nothing pulled yet._\n'
        fi
    } > "${nav_file}.new"
    mv -- "${nav_file}.new" "$nav_file"
}

# ── Commands ────────────────────────────────────────────────────

cmd_check() {
    prepare
    local out
    out="$(new_tmp)"
    api_get "action=query&meta=userinfo|siteinfo&uiprop=rights&siprop=general|statistics" "$out"
    log "logged in to $(jq -r '.query.general.sitename' "$out") ($(jq -r '.query.general.generator' "$out")) as $(jq -r '.query.userinfo.name' "$out")"
    log "the wiki holds $(jq -r '.query.statistics.articles' "$out") content page(s), $(jq -r '.query.statistics.pages' "$out") page(s) in all"
    if jq -e '.query.userinfo.rights | any(. == "edit" or . == "delete" or . == "upload")' "$out" >/dev/null; then
        warn "this bot password may edit; recreate it at Special:BotPasswords with only 'Basic rights' so the server enforces read-only"
    else
        log "login is read-only on the server side"
    fi
}

cmd_pull() {
    local index=false
    while (( $# > 0 )); do
        case "$1" in
            --index) index=true ;;
            *) die "pull: unknown option '$1'" "$ex_usage" ;;
        esac
        shift
    done

    prepare
    fetched_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    kb init >/dev/null
    namespaces_file="$(new_tmp)"
    api_get "action=query&meta=siteinfo&siprop=namespaces" "$namespaces_file"
    jq '.query.namespaces | map_values(.name)' "$namespaces_file" > "${namespaces_file}.json"
    tmp_paths+=("${namespaces_file}.json")
    namespaces_file="${namespaces_file}.json"

    local wanted changed_ids pruned id
    wanted="$(new_tmp)"
    changed_ids="$(new_tmp)"
    list_wanted "$wanted"
    pull_pages "$wanted" "$changed_ids"
    pruned="$(kb prune < "$wanted")"
    if [[ -n "$pruned" ]]; then
        log "removed from the mirror: $(printf '%s' "$pruned" | tr '\n' ' ')"
    fi
    while IFS= read -r id; do
        [[ -n "$id" ]] && changed+=("$id")
    done < <(cat -- "$changed_ids"; printf '%s\n' "$pruned")
    write_navigation_map "$changed_ids"
    log "pull done: ${#changed[@]} page(s) changed"

    if [[ "$index" == true ]]; then
        # Embeddings for every page whose indexed flag is 0 — also those a
        # previous run left behind, so this runs even when nothing changed.
        "$kb_script" index || warn "pull succeeded but embedding failed — run: ${kb_script} index"
        if (( ${#changed[@]} == 0 )); then
            log "nothing changed, graph left as is"
        elif [[ -x "$cbm_script" ]]; then
            "$cbm_script" index "$script_dir" || warn "pull succeeded but re-indexing failed — run: ${cbm_script} index ${script_dir}"
        else
            warn "cannot re-index: ${cbm_script} not found"
        fi
    fi
}

url_decode() {
    printf '%s' "$1" | python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read()))'
}

cmd_add() {
    local what="${1:-}" next title
    [[ -n "$what" ]] || die "add: give a page link or title, Category:<name>, or ns:<number>" "$ex_usage"
    (( $# == 1 )) || die "add: one thing at a time" "$ex_usage"
    require_tools

    if [[ "$what" =~ ^ns:([0-9]+)$ ]]; then
        next="$(jq --argjson n "${BASH_REMATCH[1]}" '.namespaces = ((.namespaces // []) + [$n] | unique)' "$sources_file")"
        log "namespace ${BASH_REMATCH[1]} added to sources.json"
    else
        title="$what"
        if [[ "$title" =~ ^https?:// ]]; then
            if [[ "$title" =~ [?\&]title=([^\&#]+) ]] || [[ "$title" =~ /index\.php/([^?#]+) ]] || [[ "$title" =~ /wiki/([^?#]+) ]]; then
                title="$(url_decode "${BASH_REMATCH[1]}")"
            else
                die "add: cannot find a page title in that link" "$ex_usage"
            fi
        fi
        title="${title//_/ }"
        if [[ "$title" =~ ^[Cc]ategory:(.+)$ ]]; then
            next="$(jq --arg c "${BASH_REMATCH[1]}" '.categories = ((.categories // []) + [$c] | unique)' "$sources_file")"
            log "Category:${BASH_REMATCH[1]} added to sources.json"
        else
            next="$(jq --arg t "$title" '.pages = ((.pages // []) + [$t] | unique)' "$sources_file")"
            log "page '${title}' added to sources.json"
        fi
    fi
    printf '%s\n' "$next" > "${sources_file}.new"
    mv -- "${sources_file}.new" "$sources_file"
    cmd_pull --index
}

cmd_schedule() {
    if [[ "$(uname -s)" == Darwin ]]; then
        mkdir -p "$(dirname -- "$launchd_plist")" "${HOME}/Library/Logs"
        cat > "$launchd_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>${launchd_label}</string>
    <key>ProgramArguments</key>
    <array><string>${script_dir}/sync.sh</string><string>pull</string><string>--index</string></array>
    <key>EnvironmentVariables</key>
    <dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string></dict>
    <key>StartCalendarInterval</key>
    <dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
    <key>StandardOutPath</key><string>${HOME}/Library/Logs/${unit_name}.log</string>
    <key>StandardErrorPath</key><string>${HOME}/Library/Logs/${unit_name}.log</string>
</dict>
</plist>
EOF
        launchctl bootout "gui/$(id -u)/${launchd_label}" 2>/dev/null || true
        launchctl bootstrap "gui/$(id -u)" "$launchd_plist"
        log "weekly refresh scheduled (launchd ${launchd_label}); logs: ~/Library/Logs/${unit_name}.log"
        return
    fi
    command -v systemctl >/dev/null 2>&1 || die "neither launchd nor systemctl found" "$ex_unavailable"
    mkdir -p "$unit_dir"
    cat > "${unit_dir}/${unit_name}.service" <<EOF
[Unit]
Description=Refresh the read-only wiki mirror in ${script_dir}

[Service]
Type=oneshot
ExecStart=${script_dir}/sync.sh pull --index
EOF
    cat > "${unit_dir}/${unit_name}.timer" <<EOF
[Unit]
Description=Weekly refresh of the wiki mirror

[Timer]
OnCalendar=Mon *-*-* 09:00:00
Persistent=true
RandomizedDelaySec=10min

[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now "${unit_name}.timer"
    log "logs: journalctl --user -u ${unit_name}.service"
}

cmd_unschedule() {
    if [[ "$(uname -s)" == Darwin ]]; then
        launchctl bootout "gui/$(id -u)/${launchd_label}" 2>/dev/null || true
        rm -f -- "$launchd_plist"
    else
        systemctl --user disable --now "${unit_name}.timer" 2>/dev/null || true
        rm -f -- "${unit_dir}/${unit_name}.service" "${unit_dir}/${unit_name}.timer"
        systemctl --user daemon-reload
    fi
    log "weekly refresh removed"
}

main() {
    local command="${1:-help}"
    (( $# > 0 )) && shift
    case "$command" in
        check)      cmd_check "$@" ;;
        pull)       cmd_pull "$@" ;;
        add)        cmd_add "$@" ;;
        schedule)   cmd_schedule "$@" ;;
        unschedule) cmd_unschedule "$@" ;;
        help|-h|--help) usage ;;
        *) usage >&2; exit "$ex_usage" ;;
    esac
}

main "$@"
