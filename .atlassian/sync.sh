#!/usr/bin/env bash
#
# sync.sh — keep a local, read-only mirror of Jira issues and Confluence pages
# that the codebase-memory graph can index.
#
# What lands on disk is the servers' own source, not a re-rendering:
#   .db/confluence.db                pages and comments as storage-format XHTML,
#                                    with version, updated_at and the indexed
#                                    flag; read and searched with kb.sh
#   .jira/<status>/<KEY>.json        the issue's fields; text stays in Jira wiki markup
#   navigation_map.md                the index — read it first, open one file
#
# Read-only by construction: api_get is the only function that sends a request
# with credentials, and it sends GET and nothing else — no body, no other
# method, no redirects, https only. It talks only to the two hosts in
# sources.json, both under ${allowed_host_suffix}, and only after the server
# presents the public key pinned there. Credentials reach curl through a pipe,
# never argv.
#
# Usage: ./sync.sh <command> [options]   ( ./sync.sh help )

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
workspace_dir="$(cd -- "${script_dir}/.." && pwd)"
readonly workspace_dir
readonly sources_file="${script_dir}/sources.json"
readonly cache_dir="${script_dir}/.cache"
readonly confluence_dir="${script_dir}/.confluence"   # the old per-file mirror, migrated once
readonly kb_py="${script_dir}/kb/kb.py"
readonly kb_script="${script_dir}/kb.sh"
export KB_DB="${script_dir}/.db/confluence.db"
readonly jira_dir="${script_dir}/.jira"
readonly nav_file="${script_dir}/navigation_map.md"
readonly cbm_script="${workspace_dir}/docker/cbm/cbm.sh"

readonly config_dir="${JO_ATLASSIAN_CONFIG:-${script_dir}/.secrets}"   # git- and cbm-ignored
readonly credentials_file="${config_dir}/credentials"
readonly certs_dir="${config_dir}/certs"
readonly keyring_service="jo-atlassian"
readonly unit_name="jo-atlassian-sync"
readonly unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

# The only hosts a credential is ever sent to.
readonly allowed_host_suffix=".group.jenoptik.corp"

readonly jira_batch=50
readonly confluence_batch=100
readonly confluence_fetch_batch=25
readonly jira_base_fields="summary,status,issuetype,priority,assignee,reporter,created,updated,resolution,labels,components,fixVersions,parent,subtasks,issuelinks,description,comment"

# Exit codes: 64 usage, 65 bad data, 69 unavailable (network/server), 70 internal, 78 config.
readonly ex_usage=64
readonly ex_dataerr=65
readonly ex_unavailable=69
readonly ex_software=70
readonly ex_config=78

declare -A base_urls=()
declare -A pins=()
declare -A seen_pages=()      # id -> how its comments are kept: space | page | none
declare -A page_versions=()   # id -> version the server reports
declare -A seen_issues=()
atlassian_user=""
atlassian_password=""
tls_mode=""          # "ca" when certs_dir holds a CA, else "pin-only"
ca_bundle=""
changed=()
tmp_paths=()
pulled_pages=0
max_pages=100
max_pages_warned=false
fetched_at=""
curl_err=""

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
    path="$(mktemp "${TMPDIR:-/tmp}/jo-atlassian.XXXXXX")"
    tmp_paths+=("$path")
    printf '%s' "$path"
}

usage() {
    cat <<EOF
Usage: ./sync.sh <command> [options]

  check               Log in to each service and print who you are
  pull [--index]      Refresh everything in sources.json; only what changed is
                      downloaded and rewritten. --index re-indexes the graph.
  add <link> [--children N]
                      Add a Confluence page or space link, or a Jira link /
                      issue key, to sources.json, then pull
  login               Store your password in the GNOME keyring (needs secret-tool)
  pin [--write]       Show the servers' current public-key pins; --write
                      replaces the ones in sources.json (after a cert renewal)
  schedule | unschedule
                      Install / remove the weekly systemd user timer
                      (Mondays 09:00, caught up after boot if missed)
  help                This text

Config dir:  ${config_dir}
  credentials   ATLASSIAN_USER=… and ATLASSIAN_PASSWORD=…, mode 600
                (or only ATLASSIAN_USER, with the password in the keyring)
  certs/        optional *.pem / *.crt — the Jenoptik CA chain, once you have it
EOF
}

# ── Configuration ───────────────────────────────────────────────

require_tools() {
    local tool
    for tool in curl jq openssl python3; do
        command -v "$tool" >/dev/null 2>&1 || die "${tool} is required" "$ex_unavailable"
    done
    [[ -f "$sources_file" ]] || die "missing ${sources_file}" "$ex_config"
    jq -e . "$sources_file" >/dev/null 2>&1 || die "${sources_file} is not valid JSON" "$ex_config"
}

services() {
    jq -r 'to_entries[] | select(.value.base_url) | .key' "$sources_file"
}

host_of() { # service
    local host="${base_urls[$1]#https://}"
    printf '%s' "${host%%/*}"
}

# Vet each configured service: https, under the allowed suffix, with a pin.
load_services() {
    local service url pin
    while IFS= read -r service; do
        case "$service" in jira|confluence) ;; *) die "sources.json: unknown service '${service}'" "$ex_config" ;; esac
        url="$(jq -r --arg s "$service" '.[$s].base_url' "$sources_file")"
        url="${url%/}"
        [[ "$url" =~ ^https://([A-Za-z0-9.-]+)$ ]] \
            || die "sources.json: ${service}.base_url must be https://<host> with no path" "$ex_config"
        [[ "${BASH_REMATCH[1]}" == *"$allowed_host_suffix" ]] \
            || die "refusing ${BASH_REMATCH[1]}: not under ${allowed_host_suffix}" "$ex_config"
        pin="$(jq -r --arg s "$service" '.[$s].pin // ""' "$sources_file")"
        [[ "$pin" =~ ^sha256//[A-Za-z0-9+/]{43}=$ ]] \
            || die "sources.json: ${service}.pin missing or malformed — run ./sync.sh pin" "$ex_config"
        base_urls["$service"]="$url"
        pins["$service"]="$pin"
    done < <(services)
    (( ${#base_urls[@]} > 0 )) || die "sources.json configures neither jira nor confluence" "$ex_config"
}

# A CA in certs/ upgrades the check from "this exact key" to "this exact key,
# signed by Jenoptik". Without one, the pin alone authenticates the server.
load_tls() {
    local -a found=()
    if [[ -d "$certs_dir" ]]; then
        mapfile -t found < <(find "$certs_dir" -maxdepth 1 -type f \( -name '*.pem' -o -name '*.crt' \) | sort)
    fi
    if (( ${#found[@]} > 0 )); then
        ca_bundle="$(new_tmp)"
        cat -- "${found[@]}" > "$ca_bundle"
        tls_mode="ca"
    else
        tls_mode="pin-only"
    fi
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
    if [[ -f "$credentials_file" ]]; then
        local mode line key value number=0
        mode="$(stat -c '%a' -- "$credentials_file")"
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
                ATLASSIAN_USER) atlassian_user="$value" ;;
                ATLASSIAN_PASSWORD) atlassian_password="$value" ;;
                *) die "credentials line ${number}: unknown key '${key}'" "$ex_config" ;;
            esac
        done < "$credentials_file"
    fi

    if [[ -z "$atlassian_password" ]] && command -v secret-tool >/dev/null 2>&1; then
        if [[ -z "$atlassian_user" ]]; then
            atlassian_user="$(secret-tool search service "$keyring_service" 2>&1 \
                | sed -n 's/^attribute\.account = //p' | head -n 1)" || true
        fi
        if [[ -n "$atlassian_user" ]]; then
            atlassian_password="$(secret-tool lookup service "$keyring_service" account "$atlassian_user" 2>/dev/null)" || true
        fi
    fi

    [[ -n "$atlassian_user" && -n "$atlassian_password" ]] \
        || die "no credentials: put ATLASSIAN_USER and ATLASSIAN_PASSWORD in ${credentials_file} (mode 600), or run ./sync.sh login" "$ex_config"
}

prepare() {
    require_tools
    load_services
    load_tls
    curl_err="$(new_tmp)"   # curl's stderr, kept apart from the status code
    load_credentials
}

# ── The network ─────────────────────────────────────────────────

curl_quote() {
    local text="${1//\\/\\\\}"
    printf '%s' "${text//\"/\\\"}"
}

# curl config on stdout, read through a pipe so the secret is never in argv.
curl_auth_config() {
    printf 'user = "%s:%s"\n' "$(curl_quote "$atlassian_user")" "$(curl_quote "$atlassian_password")"
}

# The only request this tool sends with credentials. GET, no body, no
# redirects, https only, and aborted before any byte is sent unless the
# server's public key matches the pin.
api_get() { # service path-with-query output-file
    local service="$1" path="$2" out="$3" status
    local -a tls=(--pinnedpubkey "${pins[$service]}")
    if [[ "$tls_mode" == ca ]]; then
        tls+=(--cacert "$ca_bundle")
    else
        tls+=(--insecure)   # chain not checkable without the CA; the pin authenticates instead
    fi
    status="$(curl --silent --show-error \
        --request GET \
        --proto '=https' --tlsv1.2 \
        "${tls[@]}" \
        --connect-timeout 15 --max-time 120 \
        --retry 3 --retry-delay 3 \
        --header 'Accept: application/json' \
        --config <(curl_auth_config) \
        --output "$out" \
        --write-out '%{http_code}' \
        "${base_urls[$service]}${path}" 2>"$curl_err")" || {
        status="$(cat -- "$curl_err")"   # a retry's warnings stay out of the status of a success
        case "$status" in
            *"(90)"*|*pinned*) die "${service}: the server's public key does not match the pin in sources.json — certificate renewed, or not the real server. Check, then ./sync.sh pin --write" "$ex_unavailable" ;;
            *"(6)"*|*"resolve host"*) die "${service}: cannot resolve $(host_of "$service") — is the VPN connected?" "$ex_unavailable" ;;
            *"(60)"*) die "${service}: the CA in ${certs_dir} does not verify the server — remove it or replace it" "$ex_unavailable" ;;
            *) die "${service}: GET failed: ${status}" "$ex_unavailable" ;;
        esac
    }
    case "$status" in
        200) ;;
        30?) die "${service}: HTTP ${status} — redirected to the login page, the credentials were not accepted. Stopping; repeated failures make Jira demand a CAPTCHA (clear it by logging in once in the browser)" "$ex_unavailable" ;;
        401|403) die "${service}: HTTP ${status} on GET ${path} — wrong password, CAPTCHA required, or no permission. Stopping without retry; if it persists, log in once in the browser" "$ex_unavailable" ;;
        404) die "${service}: HTTP 404 on GET ${path} — no such page or issue, or no permission to see it" "$ex_dataerr" ;;
        *) die "${service}: HTTP ${status} on GET ${path}: $(head -c 300 -- "$out" 2>/dev/null)" "$ex_unavailable" ;;
    esac
}

uri() {
    jq -rn --arg v "$1" '$v | @uri'
}

# Replace target with new content only when it differs; record the change.
install_if_changed() { # new-file target change-label
    if [[ -f "$2" ]] && cmp -s -- "$1" "$2"; then
        rm -f -- "$1"
        return 0
    fi
    mv -- "$1" "$2"
    changed+=("$3")
}

# ── Confluence ──────────────────────────────────────────────────
#
# Pages live in one SQLite file, .db/confluence.db, written through kb/kb.py
# (standard library only). A pull first decides WHICH pages to mirror and at
# what version — whole spaces (one listing request per 100 pages) and pinned
# pages with their children — then downloads only the pages whose version
# moved, 25 per request. Comments never move a page's version, so they are
# tracked on their own: per space, one listing of every comment's id and
# version; a page's comments are fetched again only when that set changed.
# Any change sets the page's `indexed` flag to 0 for kb.sh index.

kb() { python3 "$kb_py" "$@"; }

# Mirror this page at this version. The first source to reach a page decides
# how its comments are kept: "space" (by the space's comment listing), "page"
# (fetched every pull) or "none". Returns 1 once max_pages is reached.
confluence_track() { # id version comments
    [[ -n "${seen_pages[$1]:-}" ]] && return 0
    if (( pulled_pages >= max_pages )); then
        if [[ "$max_pages_warned" == false ]]; then
            warn "confluence: max_pages (${max_pages}) reached — the rest is skipped; raise confluence.max_pages in sources.json"
            max_pages_warned=true
        fi
        return 1
    fi
    seen_pages["$1"]="$3"
    page_versions["$1"]="$2"
    pulled_pages=$((pulled_pages + 1))
}

# Every current page of a space, with its version. No page text.
confluence_space() { # key with-comments
    local key="$1" mode=none start=0 size id version listing
    [[ "$2" == true ]] && mode=space
    listing="$(new_tmp)"
    log "confluence: space ${key}"
    while :; do
        api_get confluence "/rest/api/content?spaceKey=$(uri "$key")&type=page&status=current&expand=version&limit=${confluence_batch}&start=${start}" "$listing"
        while IFS=' ' read -r id version; do
            [[ "$id" =~ ^[0-9]+$ ]] || die "confluence: unexpected page id '${id}' in space ${key}" "$ex_dataerr"
            confluence_track "$id" "$version" "$mode" || return 0
        done < <(jq -r '.results[] | "\(.id) \(.version.number)"' "$listing")
        size="$(jq '.size // 0' "$listing")"
        (( size > 0 )) && [[ -n "$(jq -r '._links.next // empty' "$listing")" ]] || break
        start=$((start + size))
    done
}

# A pinned page and its children to <depth>.
confluence_visit() { # id known-version depth comments
    local id="$1" version="$2" depth="$3" comments="$4" tmp
    [[ -n "${seen_pages[$id]:-}" ]] && return 0
    tmp="$(new_tmp)"
    if [[ -z "$version" ]]; then
        api_get confluence "/rest/api/content/${id}?expand=version" "$tmp"
        version="$(jq -r '.version.number' "$tmp")"
    fi
    confluence_track "$id" "$version" "$comments" || return 0

    (( depth > 0 )) || return 0
    local start=0 size child child_version
    local -a children
    while :; do
        api_get confluence "/rest/api/content/${id}/child/page?expand=version&limit=${confluence_batch}&start=${start}" "$tmp"
        mapfile -t children < <(jq -r '.results[] | "\(.id) \(.version.number)"' "$tmp")
        size="$(jq '.size // 0' "$tmp")"
        for child in ${children[@]+"${children[@]}"}; do
            child_version="${child#* }"
            child="${child%% *}"
            [[ "$child" =~ ^[0-9]+$ ]] || die "confluence: unexpected child id '${child}'" "$ex_dataerr"
            confluence_visit "$child" "$child_version" $((depth - 1)) "$comments"
        done
        (( size >= confluence_batch )) || break
        start=$((start + size))
    done
}

# Store the pages of a content response; record the ones that changed.
confluence_store() { # response-file id...
    local id stored
    stored="$(new_tmp)"
    kb put-pages "$@" > "$stored"
    while IFS= read -r id; do
        changed+=("confluence:${id}")
    done < "$stored"
}

# Full source of the given pages, confluence_fetch_batch per request.
confluence_fetch() { # id...
    local response id
    local -a batch
    local -A got=()
    response="$(new_tmp)"
    while (( $# > 0 )); do
        batch=("${@:1:confluence_fetch_batch}")
        shift $(( $# < confluence_fetch_batch ? $# : confluence_fetch_batch ))
        log "confluence: downloading ${#batch[@]} page(s), $# to go"
        api_get confluence "/rest/api/content/search?cql=$(uri "id in ($(IFS=,; printf '%s' "${batch[*]}"))")&limit=${confluence_fetch_batch}&expand=$(uri 'body.storage,version,space,ancestors')" "$response"
        confluence_store "$response" "${batch[@]}"
        got=()
        while IFS= read -r id; do
            got["$id"]=1
        done < <(jq -r '.results[].id' "$response")
        # A search can come back short (permissions on the index, a server cap);
        # those pages are asked for one by one.
        for id in "${batch[@]}"; do
            [[ -n "${got[$id]:-}" ]] && continue
            api_get confluence "/rest/api/content/${id}?expand=$(uri 'body.storage,version,space,ancestors')" "$response"
            jq '{results: [.]}' "$response" > "${response}.one"
            mv -- "${response}.one" "$response"
            confluence_store "$response" "$id"
        done
    done
}

# Every comment of a space as "<page id> <comment id>.<version>".
confluence_comment_stamps() { # key
    local key="$1" start=0 size listing
    listing="$(new_tmp)"
    while :; do
        api_get confluence "/rest/api/content/search?cql=$(uri "space = \"${key}\" and type = comment")&expand=$(uri 'version,container')&limit=${confluence_batch}&start=${start}" "$listing"
        jq -r '.results[] | "\(.container.id) \(.id).\(.version.number)"' "$listing"
        size="$(jq '.size // 0' "$listing")"
        (( size > 0 )) && [[ -n "$(jq -r '._links.next // empty' "$listing")" ]] || break
        start=$((start + size))
    done
}

# One page's comments into the database; the stamp says which set they are.
confluence_comments() { # id [stamp]
    local tmp out
    tmp="$(new_tmp)"
    api_get confluence "/rest/api/content/$1/child/comment?expand=$(uri 'body.storage,history')&depth=all&limit=200" "$tmp"
    out="$(kb put-comments "$1" "$tmp" "${2:-}")"
    [[ -z "$out" ]] || changed+=("confluence:$1:comments")
}

confluence_drop_comments() { # id
    local out
    out="$(kb drop-comments "$1")"
    [[ -z "$out" ]] || changed+=("confluence:$1:comments")
}

# One-off move of the per-file mirror (.confluence/, .cache/confluence/) into
# the database. No network. The files go only after the import succeeded.
confluence_migrate_files() {
    [[ -d "$confluence_dir" ]] || return 0
    local imported
    imported="$(new_tmp)"
    log "confluence: moving the page files into ${KB_DB}"
    kb import-files "$confluence_dir" "${cache_dir}/confluence" > "$imported"
    log "confluence: $(wc -l < "$imported") page(s) imported"
    rm -rf -- "$confluence_dir" "${cache_dir}/confluence"
    changed+=("confluence:files-moved")
}

pull_confluence() {
    kb init
    confluence_migrate_files
    max_pages="$(jq -r '.confluence.max_pages // 100' "$sources_file")"
    [[ "$max_pages" =~ ^[0-9]+$ ]] || die "sources.json: confluence.max_pages must be a number" "$ex_config"

    # Which pages, at which version: spaces first, then pinned pages.
    local entry key id depth comments
    local -a comment_spaces=()
    while IFS= read -r entry; do
        key="$(jq -r '.key' <<<"$entry")"
        comments="$(jq -r 'if .comments == false then "false" else "true" end' <<<"$entry")"
        [[ "$key" =~ ^~?[A-Za-z0-9_]+$ ]] || die "sources.json: confluence space key '${key}' is not a space key" "$ex_config"
        confluence_space "$key" "$comments"
        [[ "$comments" == true ]] && comment_spaces+=("$key")
    done < <(jq -c '.confluence.spaces // [] | .[]' "$sources_file")
    while IFS= read -r entry; do
        id="$(jq -r '.id | tostring' <<<"$entry")"
        depth="$(jq -r '.descendants // 0' <<<"$entry")"
        comments="$(jq -r 'if .comments == false then "none" else "page" end' <<<"$entry")"
        [[ "$id" =~ ^[0-9]+$ ]] || die "sources.json: confluence page id '${id}' is not numeric" "$ex_config"
        [[ "$depth" =~ ^[0-9]+$ ]] || die "sources.json: descendants of ${id} must be a number" "$ex_config"
        confluence_visit "$id" "" "$depth" "$comments"
    done < <(jq -c '.confluence.pages // [] | .[]' "$sources_file")

    # Text only for what is new or whose version moved.
    local listing version
    local -a stale=()
    declare -A stored_versions=()
    listing="$(new_tmp)"
    kb versions > "$listing"
    while IFS=' ' read -r id version; do
        stored_versions["$id"]="$version"
    done < "$listing"
    for id in "${!seen_pages[@]}"; do
        [[ "${stored_versions[$id]:-}" == "${page_versions[$id]}" ]] || stale+=("$id")
    done
    log "confluence: ${#seen_pages[@]} page(s) tracked, ${#stale[@]} to download"
    if (( ${#stale[@]} > 0 )); then
        confluence_fetch "${stale[@]}"
    fi

    # Comments: a space's pages by their comment stamps, pinned pages always.
    local stamps current
    declare -A page_stamps=() stored_stamps=()
    stamps="$(new_tmp)"
    for key in ${comment_spaces[@]+"${comment_spaces[@]}"}; do
        log "confluence: comments in ${key}"
        confluence_comment_stamps "$key" >> "$stamps"
    done
    while IFS=' ' read -r id current; do
        page_stamps["$id"]="$current"
    done < <(sort "$stamps" | awk '{s[$1] = s[$1] " " $2} END {for (p in s) print p s[p]}')
    kb stamps > "$listing"
    while IFS=' ' read -r id current; do
        stored_stamps["$id"]="$current"
    done < "$listing"
    for id in "${!seen_pages[@]}"; do
        case "${seen_pages[$id]}" in
            page)
                confluence_comments "$id" ;;
            space)
                current="${page_stamps[$id]:-}"
                if [[ -z "$current" ]]; then
                    confluence_drop_comments "$id"
                elif [[ "${stored_stamps[$id]:-}" != "$current" ]]; then
                    confluence_comments "$id" "$current"
                fi ;;
            *)
                confluence_drop_comments "$id" ;;
        esac
    done

    # Pages no longer reachable from sources.json leave the mirror.
    local removed
    removed="$(new_tmp)"
    printf '%s\n' "${!seen_pages[@]}" | kb prune > "$removed"
    while IFS= read -r id; do
        changed+=("confluence:${id}:removed")
    done < "$removed"
}

# ── Jira ────────────────────────────────────────────────────────

# Every key a JQL matches, with its last update: "KEY<TAB>updated" per line.
# Asks for one field only, so a pull of unchanged issues stays small.
jira_list() { # endpoint jql max
    local endpoint="$1" jql="$2" max="$3" start=0 count total page
    page="$(new_tmp)"
    while :; do
        api_get jira "${endpoint}?jql=$(uri "$jql")&startAt=${start}&maxResults=${jira_batch}&fields=updated" "$page"
        jq -r '.issues[] | "\(.key)\t\(.fields.updated)"' "$page"
        count="$(jq '.issues | length' "$page")"
        total="$(jq '.total // 0' "$page")"
        start=$((start + count))
        (( count > 0 && start < total )) || break
        if (( start >= max )); then
            warn "jira: '${jql}' matches ${total} issues; stopped at max_issues_per_query (${max})"
            break
        fi
    done
}

# Sprint and Epic Link are custom fields whose ids differ per instance.
# The catalogue is fetched once and kept in the cache.
jira_custom_field() { # display-name -> id, or "-"
    local fields="${cache_dir}/jira/fields.json"
    if [[ ! -f "$fields" ]]; then
        api_get jira /rest/api/2/field "${fields}.new"
        mv -- "${fields}.new" "$fields"
    fi
    jq -r --arg n "$1" 'map(select(.name == $n))[0].id // "-"' "$fields"
}

# Issues sit in one folder per status: .jira/<folder>/<KEY>.json. The folder
# is jira.status_folders[status] from sources.json (several statuses may share
# one), else the status as a slug ("Selected for Development" →
# selected-for-development).
jira_status_dir() { # status
    local dir
    dir="$(jq -rn --arg s "$1" --slurpfile src "$sources_file" '
        ($src[0].jira.status_folders // {})[$s]
        // ($s | ascii_downcase | gsub("[^a-z0-9]+"; "-") | ltrimstr("-") | rtrimstr("-"))
        | if . == "" then "no-status" else . end')"
    [[ "$dir" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "jira: status folder '${dir}' for '$1' is not a plain folder name" "$ex_config"
    printf '%s' "$dir"
}

# The issue's current file, whichever status folder it is in; empty if none.
jira_issue_file() { # key
    local file
    for file in "${jira_dir}"/*/"$1".json; do
        [[ -e "$file" ]] && { printf '%s' "$file"; return 0; }
    done
    return 0
}

# One-off move of issues pulled before status folders existed. No network.
jira_migrate_flat() {
    local file key dir
    for file in "${jira_dir}"/*.json; do
        [[ -e "$file" ]] || continue
        key="$(basename -- "$file" .json)"
        dir="$(jira_status_dir "$(jq -r '.status // ""' "$file")")"
        mkdir -p -- "${jira_dir}/${dir}"
        mv -- "$file" "${jira_dir}/${dir}/${key}.json"
        changed+=("jira:${key}:moved")
    done
}

# Download the full fields of the given keys and write one trimmed file each.
jira_fetch() { # key...
    local sprint epic fields page
    jira_custom_field Sprint >/dev/null   # fetch the catalogue in this shell, so a failure stops the pull
    sprint="$(jira_custom_field Sprint)"
    epic="$(jira_custom_field 'Epic Link')"
    fields="$jira_base_fields"
    [[ "$sprint" != - ]] && fields+=",${sprint}"
    [[ "$epic" != - ]] && fields+=",${epic}"
    page="$(new_tmp)"

    local -a batch
    while (( $# > 0 )); do
        batch=("${@:1:jira_batch}")
        shift $(( $# < jira_batch ? $# : jira_batch ))
        log "jira: downloading ${batch[*]}"
        api_get jira "/rest/api/2/search?jql=$(uri "key in ($(IFS=,; printf '%s' "${batch[*]}"))")&maxResults=${jira_batch}&fields=$(uri "$fields")" "$page"
        local key
        while IFS= read -r key; do
            jq --arg k "$key" --arg base "${base_urls[jira]}" --arg sprint "$sprint" --arg epic "$epic" '
                .issues[] | select(.key == $k) | .fields as $f
                | {
                    key, url: "\($base)/browse/\(.key)",
                    summary: $f.summary, type: $f.issuetype.name, status: $f.status.name,
                    resolution: $f.resolution.name, priority: $f.priority.name,
                    assignee: $f.assignee.displayName, reporter: $f.reporter.displayName,
                    created: $f.created, updated: $f.updated,
                    labels: $f.labels, components: [$f.components[]?.name], fix_versions: [$f.fixVersions[]?.name],
                    epic: (if $epic != "-" then $f[$epic] else null end),
                    sprint: (if $sprint != "-" then [$f[$sprint][]? | if type == "string"
                               then ((capture("name=(?<n>[^,\\]]+)") | .n) // .) else .name end] else null end),
                    parent: ($f.parent | if . then {key, summary: .fields.summary} else null end),
                    subtasks: [$f.subtasks[]? | {key, summary: .fields.summary, status: .fields.status.name}],
                    links: [$f.issuelinks[]? | (.outwardIssue // .inwardIssue) as $o
                            | {relation: (if .outwardIssue then .type.outward else .type.inward end),
                               key: $o.key, summary: $o.fields.summary, status: $o.fields.status.name}],
                    description: $f.description,
                    comments: [$f.comment.comments[]? | {author: .author.displayName, created, body}]
                  }
                | with_entries(select(.value != null and .value != [] and .value != ""))' \
                "$page" > "${jira_dir}/${key}.json.new"
            local dir target old
            dir="$(jira_status_dir "$(jq -r '.status // ""' "${jira_dir}/${key}.json.new")")"
            target="${jira_dir}/${dir}/${key}.json"
            old="$(jira_issue_file "$key")"
            if [[ -n "$old" && "$old" != "$target" ]]; then
                rm -f -- "$old"   # status changed: the issue moves folder
            fi
            mkdir -p -- "${jira_dir}/${dir}"
            install_if_changed "${jira_dir}/${key}.json.new" "$target" "jira:${key}"
        done < <(jq -r '.issues[].key' "$page")
    done
}

pull_jira() {
    mkdir -p "${cache_dir}/jira" "$jira_dir"
    jira_migrate_flat
    local max entry name jql key updated board quick extra listing
    local -a stale=()
    local queries="[]"
    max="$(jq -r '.jira.max_issues_per_query // 200' "$sources_file")"
    declare -A latest=()

    # Each source: a name, an endpoint and a JQL.
    local sources_tsv
    sources_tsv="$(new_tmp)"
    local -a explicit
    mapfile -t explicit < <(jq -r '.jira.issues // [] | .[]' "$sources_file")
    for key in ${explicit[@]+"${explicit[@]}"}; do
        [[ "$key" =~ ^[A-Z][A-Z0-9_]+-[0-9]+$ ]] || die "sources.json: '${key}' is not an issue key" "$ex_config"
    done
    if (( ${#explicit[@]} > 0 )); then
        jq -cn --arg q "key in ($(IFS=,; printf '%s' "${explicit[*]}"))" \
            '{name: "pinned issues", endpoint: "/rest/api/2/search", jql: $q}' >> "$sources_tsv"
    fi
    jq -c '.jira.jql // [] | .[] | {name, endpoint: "/rest/api/2/search", jql: .query}' "$sources_file" >> "$sources_tsv"
    while IFS= read -r entry; do
        board="$(jq -r '.id | tostring' <<<"$entry")"
        quick="$(jq -r '.quick_filter // "" | tostring' <<<"$entry")"
        extra="$(jq -r '.jql // ""' <<<"$entry")"
        name="$(jq -r --arg b "$board" '.name // "board \($b)"' <<<"$entry")"
        [[ "$board" =~ ^[0-9]+$ ]] || die "sources.json: board id '${board}' is not numeric" "$ex_config"
        jql="$extra"
        if [[ -n "$quick" ]]; then
            [[ "$quick" =~ ^[0-9]+$ ]] || die "sources.json: quick_filter '${quick}' is not numeric" "$ex_config"
            listing="$(new_tmp)"
            api_get jira "/rest/agile/1.0/board/${board}/quickfilter/${quick}" "$listing"
            local quick_jql
            quick_jql="$(jq -r '.jql // ""' "$listing")"
            [[ -n "$quick_jql" ]] && jql="(${quick_jql})${extra:+ AND (${extra})}"
        fi
        jq -cn --arg n "$name" --arg e "/rest/agile/1.0/board/${board}/issue" --arg q "$jql" \
            '{name: $n, endpoint: $e, jql: $q}' >> "$sources_tsv"
    done < <(jq -c '.jira.boards // [] | .[]' "$sources_file")

    # Phase 1: keys and update stamps only.
    while IFS= read -r entry; do
        name="$(jq -r '.name' <<<"$entry")"
        jql="$(jq -r '.jql' <<<"$entry")"
        log "jira: ${name}"
        listing="$(new_tmp)"
        jira_list "$(jq -r '.endpoint' <<<"$entry")" "$jql" "$max" > "$listing"
        while IFS=$'\t' read -r key updated; do
            [[ "$key" =~ ^[A-Z][A-Z0-9_]+-[0-9]+$ ]] || die "jira: unexpected issue key '${key}'" "$ex_dataerr"
            latest["$key"]="$updated"
        done < "$listing"
        queries="$(jq -c --arg n "$name" --arg q "$jql" --rawfile k "$listing" \
            '. + [{name: $n, query: $q, keys: ($k | split("\n") | map(select(length > 0) | split("\t")[0]))}]' <<<"$queries")"
    done < "$sources_tsv"
    printf '%s\n' "$queries" > "${cache_dir}/jira/queries.json"

    # Phase 2: full download only for what is new or was updated since.
    local current
    for key in "${!latest[@]}"; do
        seen_issues["$key"]=1
        current="$(jira_issue_file "$key")"
        if [[ -z "$current" ]] \
            || [[ "$(jq -r '.updated // ""' "$current")" != "${latest[$key]}" ]]; then
            stale+=("$key")
        fi
    done
    if (( ${#stale[@]} > 0 )); then
        jira_fetch "${stale[@]}"
    else
        log "jira: nothing changed"
    fi

    local file
    for file in "${jira_dir}"/*/*.json; do
        [[ -e "$file" ]] || continue
        key="$(basename -- "$file" .json)"
        if [[ -z "${seen_issues[$key]:-}" ]]; then
            rm -f -- "$file"
            changed+=("jira:${key}:removed")
        fi
    done
    find "$jira_dir" -mindepth 1 -maxdepth 1 -type d -empty -delete
}

# ── Navigation map ──────────────────────────────────────────────

write_navigation_map() {
    local changed_json issues_index
    changed_json="$(printf '%s\n' ${changed[@]+"${changed[@]}"} | jq -Rsc 'split("\n") | map(select(length > 0))')"
    issues_index="$(new_tmp)"
    if compgen -G "${jira_dir}/*/*.json" >/dev/null; then
        jq -n --arg root "${script_dir}/" '[inputs | {(.key): {type, status, summary, updated,
                path: (input_filename | ltrimstr($root))}}] | add' "${jira_dir}"/*/*.json > "$issues_index"
    else
        printf '{}\n' > "$issues_index"
    fi

    {
        printf '# Atlassian navigation map\n\n'
        printf '> Generated by `sync.sh` — last pull %s. Read this first, then open only the file you need.\n' "$fetched_at"
        printf '> ★ = changed in the last pull. Everything is the servers'"'"' own source: Confluence storage XHTML (in the database), Jira fields with wiki-markup text.\n\n'

        printf '## Confluence\n\n'
        if [[ -f "$KB_DB" ]]; then
            printf '%s\n' ${changed[@]+"${changed[@]}"} | kb nav-map
        else
            printf '_Nothing pulled yet._\n'
        fi
        printf '\n## Jira\n\n'
        if [[ "$(jq 'length' "$issues_index")" -gt 0 ]]; then
            printf 'One folder per status, `.jira/<folder>/<KEY>.json`:\n\n'
            jq -r 'to_entries | group_by(.value.path | split("/")[1])[]
                   | "- `\(.[0].value.path | split("/")[1])/` (\([.[].value.status] | unique | join(", "))): "
                     + ([.[].key] | sort | join(", "))' "$issues_index"
            printf '\n'
        fi
        if [[ -f "${cache_dir}/jira/queries.json" ]]; then
            jq -r --slurpfile idx "$issues_index" --argjson changed "$changed_json" '
                .[] | "### \(.name) — \(.keys | length)\n\n`\(.query)`\n",
                (if (.keys | length) == 0 then "_none_\n" else
                   "| key | type | status | summary | updated |\n|---|---|---|---|---|",
                   (.keys[] as $k | $idx[0][$k] as $i
                    | "| [\($k)](\($i.path // ".jira/\($k).json"))\(if ($changed | index("jira:\($k)")) then " ★" else "" end) "
                      + "| \($i.type // "") | \($i.status // "") | \(($i.summary // "") | gsub("\\|"; "\\|")) "
                      + "| \(($i.updated // "")[0:10]) |"),
                   ""
                 end)' "${cache_dir}/jira/queries.json"
        else
            printf '_Nothing pulled yet._\n'
        fi
    } > "${nav_file}.new"
    mv -- "${nav_file}.new" "$nav_file"
}

# ── Commands ────────────────────────────────────────────────────

cmd_check() {
    prepare
    log "tls: ${tls_mode}$([[ "$tls_mode" == ca ]] && printf ' + pin' || printf ' (public-key pin)')"
    local out
    out="$(new_tmp)"
    if [[ -n "${base_urls[jira]:-}" ]]; then
        api_get jira /rest/api/2/myself "$out"
        log "jira: logged in as $(jq -r '"\(.displayName) (\(.name))"' "$out")"
    fi
    if [[ -n "${base_urls[confluence]:-}" ]]; then
        api_get confluence /rest/api/user/current "$out"
        [[ "$(jq -r '.type // ""' "$out")" != anonymous ]] \
            || die "confluence: treated as anonymous — the credentials were not accepted" "$ex_unavailable"
        log "confluence: logged in as $(jq -r '"\(.displayName) (\(.username))"' "$out")"
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
    if [[ -n "${base_urls[confluence]:-}" ]]; then
        pull_confluence
    fi
    if [[ -n "${base_urls[jira]:-}" ]]; then
        pull_jira
    fi
    write_navigation_map
    log "pull done: ${#changed[@]} file(s) changed${changed[*]:+ — ${changed[*]}}"

    if [[ "$index" == true ]]; then
        # Embeddings for every page whose indexed flag is 0 — also those a
        # previous run left behind, so this runs even when nothing changed.
        if [[ -n "${base_urls[confluence]:-}" ]]; then
            "$kb_script" index || warn "pull succeeded but embedding failed — run: ${kb_script} index"
        fi
        if (( ${#changed[@]} == 0 )); then
            log "nothing changed, graph left as is"
        elif [[ -x "$cbm_script" ]]; then
            "$cbm_script" index "$script_dir" || warn "pull succeeded but re-indexing failed — run: ${cbm_script} index ${script_dir}"
        else
            warn "cannot re-index: ${cbm_script} not found"
        fi
    fi
}

cmd_add() {
    local link="${1:-}" children=0
    [[ -n "$link" ]] || die "add: give a Confluence page link, a Jira link or an issue key" "$ex_usage"
    shift
    while (( $# > 0 )); do
        case "$1" in
            --children) children="${2:-}"; shift ;;
            *) die "add: unknown option '$1'" "$ex_usage" ;;
        esac
        shift
    done
    [[ "$children" =~ ^[0-9]+$ ]] || die "add: --children takes a number" "$ex_usage"
    require_tools

    local next
    if [[ "$link" =~ (/pages/|pageId=)([0-9]+) ]]; then
        local id="${BASH_REMATCH[2]}"
        next="$(jq --arg id "$id" --argjson d "$children" '
            if any(.confluence.pages[]?; (.id | tostring) == $id)
            then (.confluence.pages[] | select((.id | tostring) == $id) | .descendants) = $d
            else .confluence.pages += [{id: $id, descendants: $d, comments: true}] end' "$sources_file")"
        log "confluence page ${id} (children: ${children}) added to sources.json"
    elif [[ "$link" =~ (/spaces/|/display/|spaceKey=)(~?[A-Za-z0-9_]+)(/overview)?/?([?#&].*)?$ ]]; then
        local space="${BASH_REMATCH[2]}"
        next="$(jq --arg k "$space" '
            if any(.confluence.spaces[]?; .key == $k) then .
            else .confluence.spaces = ((.confluence.spaces // []) + [{key: $k, comments: true}]) end' "$sources_file")"
        log "confluence space ${space} added to sources.json"
    elif [[ "$link" =~ (selectedIssue=|/browse/|^)([A-Z][A-Z0-9_]+-[0-9]+) ]]; then
        local key="${BASH_REMATCH[2]}"
        next="$(jq --arg k "$key" '.jira.issues = ((.jira.issues // []) + [$k] | unique)' "$sources_file")"
        log "jira issue ${key} added to sources.json"
    else
        die "add: not a Confluence page link (…/pages/<id>/… or pageId=<id>), space link (…/spaces/<KEY> or …/display/<KEY>) nor a Jira key/link" "$ex_usage"
    fi
    printf '%s\n' "$next" > "${sources_file}.new"
    mv -- "${sources_file}.new" "$sources_file"
    cmd_pull --index
}

cmd_login() {
    command -v secret-tool >/dev/null 2>&1 \
        || die "secret-tool is not installed: sudo apt install libsecret-tools — or use ${credentials_file} instead" "$ex_unavailable"
    [[ -t 0 ]] || die "login is interactive: run it in your own terminal" "$ex_usage"
    local user
    read -rp "Jenoptik username: " user
    [[ -n "$user" ]] || die "no username given" "$ex_usage"
    printf 'Password (hidden): ' >&2
    secret-tool store --label="jo-atlassian (Jira/Confluence read-only mirror)" \
        service "$keyring_service" account "$user"
    log "stored in the keyring as service=${keyring_service} account=${user}"
    log "next: ${script_dir}/sync.sh check"
}

cmd_pin() {
    local write=false
    [[ "${1:-}" == --write ]] && write=true
    require_tools
    load_services
    local service host observed next
    for service in "${!base_urls[@]}"; do
        host="$(host_of "$service")"
        observed="sha256//$(openssl s_client -connect "${host}:443" -servername "$host" </dev/null 2>/dev/null \
            | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der \
            | openssl dgst -sha256 -binary | base64)" || die "${service}: cannot read the certificate of ${host}" "$ex_unavailable"
        printf '%-11s configured %s\n%-11s observed   %s%s\n' "$service" "${pins[$service]}" "" "$observed" \
            "$([[ "$observed" == "${pins[$service]}" ]] && printf '  (match)' || printf '  (DIFFERENT)')"
        if [[ "$write" == true && "$observed" != "${pins[$service]}" ]]; then
            next="$(jq --arg s "$service" --arg p "$observed" '.[$s].pin = $p' "$sources_file")"
            printf '%s\n' "$next" > "${sources_file}.new"
            mv -- "${sources_file}.new" "$sources_file"
            warn "${service}: pin replaced — confirm the new certificate fingerprint in the browser"
        fi
    done
}

cmd_schedule() {
    command -v systemctl >/dev/null 2>&1 || die "systemctl not found" "$ex_unavailable"
    mkdir -p "$unit_dir"
    cat > "${unit_dir}/${unit_name}.service" <<EOF
[Unit]
Description=Refresh the read-only Jira/Confluence mirror in ${script_dir}

[Service]
Type=oneshot
ExecStart=${script_dir}/sync.sh pull --index
EOF
    cat > "${unit_dir}/${unit_name}.timer" <<EOF
[Unit]
Description=Weekly refresh of the Jira/Confluence mirror

[Timer]
OnCalendar=Mon *-*-* 09:00:00
Persistent=true
RandomizedDelaySec=10min

[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now "${unit_name}.timer"
    systemctl --user list-timers "${unit_name}.timer" --no-pager
    log "logs: journalctl --user -u ${unit_name}.service"
}

cmd_unschedule() {
    systemctl --user disable --now "${unit_name}.timer" 2>/dev/null || true
    rm -f -- "${unit_dir}/${unit_name}.service" "${unit_dir}/${unit_name}.timer"
    systemctl --user daemon-reload
    log "weekly timer removed"
}

main() {
    local command="${1:-help}"
    (( $# > 0 )) && shift
    case "$command" in
        check)      cmd_check "$@" ;;
        pull)       cmd_pull "$@" ;;
        add)        cmd_add "$@" ;;
        login)      cmd_login "$@" ;;
        pin)        cmd_pin "$@" ;;
        schedule)   cmd_schedule "$@" ;;
        unschedule) cmd_unschedule "$@" ;;
        help|-h|--help) usage ;;
        *) usage >&2; exit "$ex_usage" ;;
    esac
}

main "$@"
