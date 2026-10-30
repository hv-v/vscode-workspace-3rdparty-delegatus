#!/usr/bin/env bash
#
# sync.sh — keep a local, read-only mirror of your GitLab merge requests:
# their review threads, their latest pipeline, and the logs of failed jobs,
# laid out so an agent reads one small file instead of the web UI.
#
#   .mr/<project path>/<iid>.json       MR fields, pipeline summary with the tail
#                                       of each failed job's log, review threads
#   .logs/<project path>/<job id>.log   a job's full log, colour codes and
#                                       section markers removed
#   navigation_map.md                   the index — read it first, open one file
#
# Read-only twice over:
#   - on the server: every request carries a token scoped read_api (or another
#     read_* scope); the script refuses a token that could write;
#   - in this client: api_get is the only function that sends a request with
#     that token, and it sends GET and nothing else — no body, no redirects,
#     https only, aborted before a byte is sent unless the server presents the
#     public key pinned in sources.json.
# With a password instead of a personal token, two more requests exist: the
# login that creates the read_api token (POST /oauth/token) and the logout
# that revokes it on exit (POST /oauth/revoke). They touch no project data.
# Secrets reach curl through a pipe, never argv.
#
# Usage: ./sync.sh <command> [options]   ( ./sync.sh help )

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
workspace_dir="$(cd -- "${script_dir}/.." && pwd)"
readonly workspace_dir
readonly sources_file="${script_dir}/sources.json"
readonly cache_dir="${script_dir}/.cache"
readonly mr_dir="${script_dir}/.mr"
readonly logs_dir="${script_dir}/.logs"
readonly nav_file="${script_dir}/navigation_map.md"
readonly cbm_script="${workspace_dir}/docker/cbm/cbm.sh"

readonly config_dir="${JO_GITLAB_CONFIG:-${script_dir}/.secrets}"   # git- and cbm-ignored
readonly credentials_file="${config_dir}/credentials"
readonly certs_dir="${config_dir}/certs"

# The only hosts a credential is ever sent to.
readonly allowed_host_suffix=".jenoptik.corp"
# Scopes a personal token may carry; anything else could write.
readonly read_only_scopes=" read_api read_user read_repository read_registry "

readonly per_page=100
readonly log_keep_days=14
readonly path_pattern='^[A-Za-z0-9_][A-Za-z0-9_.-]*(/[A-Za-z0-9_][A-Za-z0-9_.-]*)*$'
readonly ref_pattern='^([A-Za-z0-9_][A-Za-z0-9_.-]*(/[A-Za-z0-9_][A-Za-z0-9_.-]*)*)!([0-9]+)$'

# Exit codes: 64 usage, 65 bad data, 69 unavailable (network/server), 70 internal, 78 config.
readonly ex_usage=64
readonly ex_dataerr=65
readonly ex_unavailable=69
readonly ex_software=70
readonly ex_config=78

base_url=""
scheme=""            # "https", or "http" when allow_plain_http_host names this host
host=""
pin=""
group=""
tls_mode=""          # "ca" when certs_dir holds a CA, else "pin-only"
tls_args=()
gitlab_user=""
gitlab_password=""
gitlab_token=""
token_kind=""        # "private" (personal token) or "oauth" (from the password)
access_token=""
me=""
tail_lines=40
changed=()
tmp_paths=()
fetched_at=""
curl_err=""
declare -A seen=()

# A password session's token is revoked on the way out, even after an error;
# it would otherwise stay valid for its two-hour lifetime.
cleanup() {
    if [[ "$token_kind" == oauth && -n "$access_token" ]]; then
        curl --silent --request POST ${tls_args[@]+"${tls_args[@]}"} \
            --connect-timeout 10 --max-time 20 \
            --config <(printf 'data-urlencode = "token=%s"\n' "$(curl_quote "$access_token")") \
            --output /dev/null "${base_url}/oauth/revoke" 2>/dev/null || true
    fi
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
    path="$(mktemp "${TMPDIR:-/tmp}/jo-gitlab.XXXXXX")"   # mode 600
    tmp_paths+=("$path")
    printf '%s' "$path"
}

usage() {
    cat <<EOF
Usage: ./sync.sh <command> [options]

  check               Log in and print who you are and what the token may do
  pull [--index]      Refresh every tracked MR: comments only when the MR
                      changed, jobs and failed-job logs only when its latest
                      pipeline changed. --index re-indexes the graph.
  add <MR link | group/project!iid>
                      Track one more MR (even after it is merged), then pull
  log <job link | group/project job-id>
                      Download one job's log, whatever its status; prints the
                      file and its line count, not the log
  pin [--write]       Show the server's public-key pin; --write stores it in
                      sources.json (first setup, or after a cert renewal)
  help                This text

Config dir:  ${config_dir}
  credentials   GITLAB_USER=… and GITLAB_PASSWORD=…, mode 600
                (or GITLAB_TOKEN=… — a personal token with read_api only)
  certs/        optional *.pem / *.crt — the Jenoptik CA chain
EOF
}

# ── Configuration ───────────────────────────────────────────────

require_tools() {
    local tool
    for tool in curl jq openssl sed; do
        command -v "$tool" >/dev/null 2>&1 || die "${tool} is required" "$ex_unavailable"
    done
    [[ -f "$sources_file" ]] || die "missing ${sources_file}" "$ex_config"
    jq -e . "$sources_file" >/dev/null 2>&1 || die "${sources_file} is not valid JSON" "$ex_config"
}

# https, under the allowed suffix, with a pin — unless only the pin is wanted.
# Plain http only when sources.json opts in for exactly this host: the server
# may simply have no TLS, and then there is nothing to pin.
load_config() { # [allow-missing-pin]
    local plain_http_host
    base_url="$(jq -r '.base_url // ""' "$sources_file")"
    base_url="${base_url%/}"
    [[ "$base_url" =~ ^(https?)://([A-Za-z0-9.-]+)$ ]] \
        || die "sources.json: base_url must be https://<host> with no path" "$ex_config"
    scheme="${BASH_REMATCH[1]}"
    host="${BASH_REMATCH[2]}"
    [[ "$host" == *"$allowed_host_suffix" ]] || die "refusing ${host}: not under ${allowed_host_suffix}" "$ex_config"
    if [[ "$scheme" == http ]]; then
        plain_http_host="$(jq -r '.allow_plain_http_host // ""' "$sources_file")"
        [[ "$plain_http_host" == "$host" ]] \
            || die "sources.json: base_url is plain http — set \"allow_plain_http_host\": \"${host}\" only if the server has no https and you accept that the password travels unencrypted" "$ex_config"
    fi

    group="$(jq -r '.group // ""' "$sources_file")"
    [[ -z "$group" || "$group" =~ $path_pattern ]] || die "sources.json: group '${group}' is not a group path" "$ex_config"
    tail_lines="$(jq -r '.log_tail_lines // 40' "$sources_file")"
    [[ "$tail_lines" =~ ^[0-9]+$ ]] || die "sources.json: log_tail_lines must be a number" "$ex_config"

    pin="$(jq -r '.pin // ""' "$sources_file")"
    [[ "$scheme" == http ]] && return 0
    [[ -z "$pin" && "${1:-}" == allow-missing-pin ]] && return 0
    [[ "$pin" =~ ^sha256//[A-Za-z0-9+/]{43}=$ ]] \
        || die "sources.json: pin missing or malformed — run ./sync.sh pin, compare it with the certificate in the browser, then ./sync.sh pin --write" "$ex_config"
}

# A CA in certs/ upgrades the check from "this exact key" to "this exact key,
# signed by Jenoptik". Without one, the pin alone authenticates the server.
load_tls() {
    local -a found=()
    local ca_bundle
    if [[ "$scheme" == http ]]; then
        tls_args=(--proto '=http')
        tls_mode="plain-http"
        warn "${host}: plain http (allow_plain_http_host) — password, token and data cross the network unencrypted, and the server is not authenticated"
        return 0
    fi
    if [[ -d "$certs_dir" ]]; then
        mapfile -t found < <(find "$certs_dir" -maxdepth 1 -type f \( -name '*.pem' -o -name '*.crt' \) | sort)
    fi
    tls_args=(--proto '=https' --tlsv1.2 --pinnedpubkey "$pin")
    if (( ${#found[@]} > 0 )); then
        ca_bundle="$(new_tmp)"
        cat -- "${found[@]}" > "$ca_bundle"
        tls_args+=(--cacert "$ca_bundle")
        tls_mode="ca"
    else
        tls_args+=(--insecure)   # chain not checkable without the CA; the pin authenticates instead
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
    [[ -f "$credentials_file" ]] \
        || die "no credentials: install -m 600 '${config_dir}/credentials.example' '${credentials_file}', then fill it in" "$ex_config"
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
            GITLAB_USER) gitlab_user="$value" ;;
            GITLAB_PASSWORD) gitlab_password="$value" ;;
            GITLAB_TOKEN) gitlab_token="$value" ;;
            *) die "credentials line ${number}: unknown key '${key}'" "$ex_config" ;;
        esac
    done < "$credentials_file"
    if [[ "$(jq -r '.password_login // true' "$sources_file")" == false ]]; then
        # Token only: a password in the file is never sent, and a missing
        # token stops here, before anything reaches the server.
        gitlab_user=""
        gitlab_password=""
        [[ -n "$gitlab_token" ]] \
            || die "credentials: password_login is off in sources.json — set GITLAB_TOKEN=… in ${credentials_file} (and save it)" "$ex_config"
    fi
    [[ -n "$gitlab_token" || ( -n "$gitlab_user" && -n "$gitlab_password" ) ]] \
        || die "credentials: set GITLAB_USER and GITLAB_PASSWORD, or GITLAB_TOKEN, in ${credentials_file}" "$ex_config"
}

prepare() {
    require_tools
    load_config
    load_tls
    curl_err="$(new_tmp)"   # curl's stderr, kept apart from the status code
    load_credentials
    login
}

# ── The network ─────────────────────────────────────────────────

curl_quote() {
    local text="${1//\\/\\\\}"
    printf '%s' "${text//\"/\\\"}"
}

# curl config on stdout, read through a pipe so the token is never in argv.
auth_config() {
    if [[ "$token_kind" == private ]]; then
        printf 'header = "PRIVATE-TOKEN: %s"\n' "$(curl_quote "$access_token")"
    else
        printf 'header = "Authorization: Bearer %s"\n' "$(curl_quote "$access_token")"
    fi
}

curl_failed() { # curl-stderr what
    case "$1" in
        *"(90)"*|*pinned*) die "the server's public key does not match the pin in sources.json — certificate renewed, or not the real server. Check, then ./sync.sh pin --write" "$ex_unavailable" ;;
        *"(6)"*|*"resolve host"*) die "cannot resolve ${host} — is the VPN connected?" "$ex_unavailable" ;;
        *"(60)"*) die "the CA in ${certs_dir} does not verify the server — remove it or replace it" "$ex_unavailable" ;;
        *"(63)"*) die "$2: larger than 100 MB, not downloaded" "$ex_dataerr" ;;
        *) die "$2 failed: $1" "$ex_unavailable" ;;
    esac
}

# The only request this tool sends with the token. GET, no body, no
# redirects, https only, and aborted before any byte is sent unless the
# server's public key matches the pin. "soft" returns 1 on 403/404 instead
# of stopping, for things that may legitimately be gone (an erased log).
api_get() { # path-with-query output-file [soft]
    local path="$1" out="$2" soft="${3:-}" status
    status="$(curl --silent --show-error \
        --request GET \
        "${tls_args[@]}" \
        --connect-timeout 15 --max-time 300 --max-filesize 104857600 \
        --retry 3 --retry-delay 3 \
        --config <(auth_config) \
        --output "$out" \
        --write-out '%{http_code}' \
        "${base_url}/api/v4${path}" 2>"$curl_err")" || curl_failed "$(cat -- "$curl_err")" "GET ${path}"
    case "$status" in
        200) return 0 ;;
        30?) die "HTTP ${status} on GET ${path} — redirected, most likely to a login page" "$ex_unavailable" ;;
        401) die "HTTP 401 on GET ${path} — the token was not accepted. Stopping without retry" "$ex_unavailable" ;;
        403|404)
            [[ -n "$soft" ]] && return 1
            die "HTTP ${status} on GET ${path} — no such object, or no permission to see it" "$ex_dataerr" ;;
        *) die "HTTP ${status} on GET ${path}: $(head -c 300 -- "$out" 2>/dev/null)" "$ex_unavailable" ;;
    esac
}

# Every page of a list endpoint, concatenated into one JSON array in <out>.
# Writes a file rather than printing, so a failed GET stops the script
# instead of dying inside a command substitution.
api_list() { # path-with-query max output-file
    local path="$1" max="$2" out="$3" page=1 count total=0 chunk sep='?'
    [[ "$path" == *\?* ]] && sep='&'
    chunk="$(new_tmp)"
    printf '[]\n' > "$out"
    while :; do
        api_get "${path}${sep}per_page=${per_page}&page=${page}" "$chunk"
        count="$(jq 'length' "$chunk")"
        jq -s '.[0] + .[1]' "$out" "$chunk" > "${chunk}.sum"
        mv -- "${chunk}.sum" "$out"
        total=$((total + count))
        (( count == per_page )) || break
        if (( total >= max )); then
            warn "${path}: stopped at ${max} entries"
            break
        fi
        page=$((page + 1))
    done
}

# Password → a read_api token for this run only. One attempt: a wrong
# password counts against the account's lockout, so it never retries.
oauth_login() {
    local out status scope stamp refused="${cache_dir}/login_refused"
    stamp="$(stat -c '%Y' -- "$credentials_file")"
    if [[ -f "$refused" && "$(cat -- "$refused")" == "$stamp" ]]; then
        die "the last login with these credentials was refused, and ${credentials_file} has not changed since — not trying again (each failure counts towards an account lockout). Edit and save it first" "$ex_config"
    fi
    out="$(new_tmp)"
    status="$(curl --silent --show-error \
        --request POST \
        "${tls_args[@]}" \
        --connect-timeout 15 --max-time 60 \
        --header 'Accept: application/json' \
        --config <(printf 'data-urlencode = "%s"\n' \
            "grant_type=password" \
            "username=$(curl_quote "$gitlab_user")" \
            "password=$(curl_quote "$gitlab_password")" \
            "scope=read_api") \
        --output "$out" \
        --write-out '%{http_code}' \
        "${base_url}/oauth/token" 2>&1)" || curl_failed "$status" "login"
    case "$status" in
        200) ;;
        400|401)
            mkdir -p -- "$cache_dir"
            printf '%s\n' "$stamp" > "$refused"
            die "login refused (HTTP ${status}: $(jq -r '[.error, .error_description] | map(select(.)) | join(" — ")' "$out" 2>/dev/null | head -c 300)). Stopping without retry: repeated failures can lock the account. Wrong password, two-factor login, or password login disabled on this server" "$ex_unavailable" ;;
        *) die "login: HTTP ${status}: $(head -c 300 -- "$out")" "$ex_unavailable" ;;
    esac
    access_token="$(jq -r '.access_token // ""' "$out")"
    scope="$(jq -r '.scope // ""' "$out")"
    [[ -n "$access_token" ]] || die "login: no token in the server's answer" "$ex_unavailable"
    token_kind=oauth   # from here on, cleanup revokes it
    rm -f -- "$refused"
    [[ "$scope" == read_api ]] \
        || die "login: the server granted scope '${scope}' instead of read_api — refusing to use it (revoked)" "$ex_unavailable"
}

login() {
    local out
    out="$(new_tmp)"
    if [[ -n "$gitlab_token" ]]; then
        token_kind=private
        access_token="$gitlab_token"
        api_get /personal_access_tokens/self "$out" soft \
            || die "cannot read this token's scopes (GitLab older than 15.5?) — refusing a token whose rights are unknown" "$ex_config"
        local scope
        for scope in $(jq -r '.scopes[]' "$out"); do
            [[ "$read_only_scopes" == *" ${scope} "* ]] \
                || die "the token has scope '${scope}', which can write — create one with read_api only" "$ex_config"
        done
    else
        oauth_login
    fi
    api_get /user "$out"
    me="$(jq -r '.username // ""' "$out")"
    [[ "$me" =~ ^[A-Za-z0-9_.-]+$ ]] || die "unexpected username in GET /user" "$ex_dataerr"
}

uri() {
    jq -rn --arg v "$1" '$v | @uri'
}

# A project path from the server, before it becomes part of a file name.
check_path() { # path
    [[ "$1" =~ $path_pattern && "/$1/" != */../* && "/$1/" != */./* ]] \
        || die "unexpected project path '$1'" "$ex_dataerr"
}

# Replace target with new content only when it differs; record the change.
install_if_changed() { # new-file target change-label
    if [[ -f "$2" ]] && cmp -s -- "$1" "$2"; then
        rm -f -- "$1"
        return 0
    fi
    mkdir -p -- "$(dirname -- "$2")"
    mv -- "$1" "$2"
    changed+=("$3")
}

# GitLab job logs: colour codes, collapsible-section markers and carriage-
# return redraws removed — the text a terminal would end up showing.
clean_log() { # raw-file output-file
    LC_ALL=C sed -E \
        -e 's/\x1b\[[0-9;?]*[A-Za-z]//g' \
        -e 's/section_(start|end):[0-9]+:[A-Za-z0-9_.-]+(\[[^]]*\])?\r?//g' \
        -e 's/\r+$//' \
        -e 's/.*\r//' \
        "$1" > "$2"
}

fetch_log() { # project-path job-id -> 0 when the log is on disk
    local path="$1" id="$2" raw target="${logs_dir}/$1/$2.log"
    raw="$(new_tmp)"
    api_get "/projects/$(uri "$path")/jobs/${id}/trace" "$raw" soft || return 1
    mkdir -p -- "$(dirname -- "$target")"
    clean_log "$raw" "${target}.new"
    mv -- "${target}.new" "$target"
}

# ── Merge requests ──────────────────────────────────────────────

# MR fields and its human review threads (system notes dropped), trimmed.
mr_meta() { # mr-json discussions-json output
    jq -n --slurpfile m "$1" --slurpfile d "$2" '
        $m[0] as $mr
        | [ $d[0][]
            | (.notes | map(select(.system | not))) as $n
            | select($n | length > 0)
            | { resolved: (if $n[0].resolvable then ($n | all(.resolved // false)) else null end),
                at: ($n[0].position | if . then "\(.new_path // .old_path):\(.new_line // .old_line // "")" else null end),
                notes: [ $n[] | {by: .author.username, at: .created_at[0:16], body} ] }
            | with_entries(select(.value != null)) ] as $threads
        | { ref: $mr.references.full, url: $mr.web_url, title: $mr.title, state: $mr.state,
            draft: ($mr.draft // $mr.work_in_progress // false),
            author: $mr.author.username,
            assignees: [$mr.assignees[]?.username], reviewers: [$mr.reviewers[]?.username],
            source_branch: $mr.source_branch, target_branch: $mr.target_branch, sha: $mr.sha,
            merge_status: ($mr.detailed_merge_status // $mr.merge_status), has_conflicts: $mr.has_conflicts,
            labels: $mr.labels, created: $mr.created_at, updated: $mr.updated_at,
            open_threads: ($threads | map(select(.resolved == false)) | length),
            description: $mr.description, threads: $threads }' > "$3"
}

# The latest pipeline, child pipelines included: counts per status, what is
# still running, and for each failed job its log on disk plus its last lines.
pipeline_snapshot() { # project-path pipeline-json output
    local path="$1" pipeline="$2" out="$3" enc pid jobs bridges sub failed job job_path job_id log_file tail_file
    enc="$(uri "$path")"
    pid="$(jq -r '.id' "$pipeline")"
    [[ "$pid" =~ ^[0-9]+$ ]] || die "unexpected pipeline id '${pid}'" "$ex_dataerr"
    jobs="$(new_tmp)"; bridges="$(new_tmp)"; sub="$(new_tmp)"; failed="$(new_tmp)"; tail_file="$(new_tmp)"
    : > "$failed"

    # An external pipeline (Jenkins and the like) has no GitLab jobs and no
    # logs here: only the commit statuses that CI reported, each linking to
    # its build on the CI server.
    if [[ "$(jq -r '.source' "$pipeline")" == external ]]; then
        local sha
        sha="$(jq -r '.sha' "$pipeline")"
        [[ "$sha" =~ ^[0-9a-f]{7,64}$ ]] || die "unexpected commit sha '${sha}'" "$ex_dataerr"
        api_list "/projects/${enc}/repository/commits/${sha}/statuses" 500 "$sub"
        jq --argjson pid "$pid" '[ .[] | select((.pipeline_id // $pid) == $pid)
            | {name, status, stage: "external", allow_failure, description, url: .target_url} ]' "$sub" > "$jobs"
        jq -c '.[] | select(.status == "failed")
               | {name, description, allow_failure, url, log: "external CI: open url (not on GitLab)"}' "$jobs" >> "$failed"
    else

    api_list "/projects/${enc}/pipelines/${pid}/jobs" 1000 "$jobs"
    api_list "/projects/${enc}/pipelines/${pid}/bridges" 200 "$bridges"
    local name project child
    while IFS=$'\t' read -r name project child; do
        [[ "$project" =~ ^[0-9]+$ && "$child" =~ ^[0-9]+$ ]] || die "unexpected downstream pipeline '${project}/${child}'" "$ex_dataerr"
        api_list "/projects/${project}/pipelines/${child}/jobs" 1000 "$sub"
        jq -s --arg via "$name" '.[0] + (.[1] | map(. + {via: $via}))' "$jobs" "$sub" > "${jobs}.sum"
        mv -- "${jobs}.sum" "$jobs"
    done < <(jq -r '.[] | select(.downstream_pipeline) | [.name, .downstream_pipeline.project_id, .downstream_pipeline.id] | @tsv' "$bridges")

    while IFS= read -r job; do
        job_path="$(jq -r '.url | capture("^https?://[^/]+/(?<p>.+)/-/jobs/[0-9]+$").p // ""' <<<"$job")"
        job_id="$(jq -r '.id' <<<"$job")"
        check_path "$job_path"
        [[ "$job_id" =~ ^[0-9]+$ ]] || die "unexpected job id '${job_id}'" "$ex_dataerr"
        log_file="${logs_dir}/${job_path}/${job_id}.log"
        if [[ -f "$log_file" ]] || fetch_log "$job_path" "$job_id"; then
            tail -n "$tail_lines" -- "$log_file" > "$tail_file"
            jq -c --arg log ".logs/${job_path}/${job_id}.log" --rawfile t "$tail_file" \
                '. + {log: $log, tail: ($t | split("\n") | map(select(test("\\S")) | .[0:400]))}' <<<"$job" >> "$failed"
        else
            jq -c '. + {log: "erased or not readable"}' <<<"$job" >> "$failed"
        fi
    done < <(jq -c '.[] | select(.status == "failed")
                    | {id, name, stage, via, allow_failure, failure_reason, url: .web_url}' "$jobs")
    fi

    jq -n --slurpfile p "$pipeline" --slurpfile j "$jobs" --slurpfile f <(jq -s . "$failed") '
        $p[0] as $pl
        | { stamp: "\($pl.id) \($pl.status) \($pl.updated_at)",
            id: $pl.id, status: $pl.status, sha: $pl.sha, source: $pl.source,
            url: $pl.web_url, updated: $pl.updated_at,
            jobs: ($j[0] | group_by(.status) | map({(.[0].status): length}) | add // {}),
            unfinished: [ $j[0][] | select(.status | IN("created", "pending", "preparing", "running", "waiting_for_resource"))
                          | "\(if .via then .via + " / " else "" end)\(.name) (\(.status))" ],
            failed: [ $f[0][] | with_entries(select(.value != null)) ] }
        | with_entries(select(.value != [] and .value != null))' > "$out"
}

# One MR: details and threads when the MR changed, jobs and logs when its
# latest pipeline changed; the published file is the two pieces joined.
mr_visit() { # ref listed-updated-at (empty: unknown)
    local ref="$1" updated="$2" path iid enc cache raw disc pipelines latest stamp target
    [[ "$ref" =~ $ref_pattern ]] || die "unexpected MR reference '${ref}'" "$ex_dataerr"
    path="${BASH_REMATCH[1]}"
    iid="${BASH_REMATCH[3]}"
    check_path "$path"
    [[ -n "${seen[$ref]:-}" ]] && return 0
    seen["$ref"]=1
    enc="$(uri "$path")"
    cache="${cache_dir}/mr/${path}/${iid}"
    target="${mr_dir}/${path}/${iid}.json"
    mkdir -p -- "$cache"
    raw="$(new_tmp)"; disc="$(new_tmp)"; pipelines="$(new_tmp)"; latest="$(new_tmp)"

    if [[ -z "$updated" ]]; then
        api_get "/projects/${enc}/merge_requests/${iid}" "$raw"
        updated="$(jq -r '.updated_at' "$raw")"
    fi
    if [[ ! -f "${cache}/meta.json" || "$(jq -r '.updated' "${cache}/meta.json")" != "$updated" ]]; then
        log "${ref}: changed — downloading the MR and its threads"
        [[ -s "$raw" ]] || api_get "/projects/${enc}/merge_requests/${iid}" "$raw"
        api_list "/projects/${enc}/merge_requests/${iid}/discussions" 2000 "$disc"
        mr_meta "$raw" "$disc" "${cache}/meta.json"
    fi

    api_get "/projects/${enc}/merge_requests/${iid}/pipelines?per_page=1" "$pipelines"
    if [[ "$(jq 'length' "$pipelines")" -eq 0 ]]; then
        printf 'null\n' > "${cache}/pipeline.json"
    else
        jq '.[0]' "$pipelines" > "$latest"
        stamp="$(jq -r '"\(.id) \(.status) \(.updated_at)"' "$latest")"
        if [[ ! -f "${cache}/pipeline.json" || "$(jq -r '.stamp // ""' "${cache}/pipeline.json")" != "$stamp" ]]; then
            log "${ref}: pipeline ${stamp% *} — downloading its jobs"
            pipeline_snapshot "$path" "$latest" "${cache}/pipeline.json.new"
            mv -- "${cache}/pipeline.json.new" "${cache}/pipeline.json"
        fi
    fi

    mkdir -p -- "$(dirname -- "$target")"
    jq -n --slurpfile m "${cache}/meta.json" --slurpfile p "${cache}/pipeline.json" '
        ($m[0] | del(.description, .threads))
        + {pipeline: ($p[0] | if . then del(.stamp) else null end)}
        + ($m[0] | {description, threads})
        | with_entries(select(.value != null and .value != [] and .value != ""))' > "${target}.new"
    install_if_changed "${target}.new" "$target" "mr:${ref}"
}

pull_mrs() {
    mkdir -p -- "${cache_dir}/mr" "$mr_dir" "$logs_dir"
    local max entry name params listing ref updated queries="[]"
    max="$(jq -r '.max_mrs_per_query // 100' "$sources_file")"
    [[ "$max" =~ ^[0-9]+$ ]] || die "sources.json: max_mrs_per_query must be a number" "$ex_config"
    listing="$(new_tmp)"

    # Phase 1: each query lists its MRs with their last update, nothing more.
    declare -A latest=()
    if [[ -n "$group" ]]; then
        while IFS= read -r entry; do
            name="$(jq -r '.name' <<<"$entry")"
            params="$(jq -r '.params' <<<"$entry")"
            params="${params//\{me\}/$me}"
            [[ "$params" =~ ^[A-Za-z0-9_.=\&-]+$ ]] || die "sources.json: query '${name}' has unexpected params" "$ex_config"
            log "query: ${name}"
            api_list "/groups/$(uri "$group")/merge_requests?${params}" "$max" "$listing"
            while IFS=$'\t' read -r ref updated; do
                latest["$ref"]="$updated"
            done < <(jq -r '.[] | [.references.full, .updated_at] | @tsv' "$listing")
            queries="$(jq -c --arg n "$name" --arg q "$params" --slurpfile l "$listing" \
                '. + [{name: $n, query: $q, refs: [$l[0][].references.full]}]' <<<"$queries")"
        done < <(jq -c '.queries // [] | .[]' "$sources_file")
    fi
    local -a pinned
    mapfile -t pinned < <(jq -r '.merge_requests // [] | .[]' "$sources_file")
    if (( ${#pinned[@]} > 0 )); then
        queries="$(jq -c '. + [{name: "pinned in sources.json", query: "merge_requests", refs: $ARGS.positional}]' \
            --args "${pinned[@]}" <<<"$queries")"
    fi
    printf '%s\n' "$queries" > "${cache_dir}/queries.json"

    # Phase 2: per MR, download only what moved.
    for ref in "${!latest[@]}"; do
        mr_visit "$ref" "${latest[$ref]}"
    done
    for ref in ${pinned[@]+"${pinned[@]}"}; do
        mr_visit "$ref" ""
    done

    # MRs no longer tracked leave the mirror; so do logs nothing points at.
    local file
    while IFS= read -r file; do
        ref="${file#"${mr_dir}/"}"
        ref="${ref%.json}"
        ref="${ref%/*}!${ref##*/}"
        if [[ -z "${seen[$ref]:-}" ]]; then
            rm -rf -- "$file" "${cache_dir}/mr/${ref%!*}/${ref##*!}"
            changed+=("mr:${ref}:removed")
        fi
    done < <(find "$mr_dir" -type f -name '*.json')
    local referenced
    referenced="$(new_tmp)"
    find "$mr_dir" -type f -name '*.json' -exec jq -r '.pipeline.failed[]?.log // empty' {} + | sort -u > "$referenced"
    while IFS= read -r file; do
        grep -qxF -- ".logs/${file#"${logs_dir}/"}" "$referenced" || rm -f -- "$file"
    done < <(find "$logs_dir" -type f -name '*.log' -mtime +"$log_keep_days")
    find "$mr_dir" "$logs_dir" "${cache_dir}/mr" -mindepth 1 -type d -empty -delete
}

# ── Navigation map ──────────────────────────────────────────────

write_navigation_map() {
    local changed_json index
    changed_json="$(printf '%s\n' ${changed[@]+"${changed[@]}"} | jq -Rsc 'split("\n") | map(select(length > 0))')"
    index="$(new_tmp)"
    find "$mr_dir" -type f -name '*.json' -exec cat {} + \
        | jq -s 'map({(.ref): {title, draft, source_branch, target_branch, updated, open_threads,
                     pipeline: .pipeline.status, failed: [.pipeline.failed[]?.name]}}) | add // {}' > "$index"

    {
        printf '# GitLab navigation map\n\n'
        printf '> Generated by `sync.sh` — last pull %s, as @%s. Read this first, then open only the file you need.\n' "$fetched_at" "$me"
        printf '> ★ = changed in the last pull. `.mr/<project>/<iid>.json`: MR fields, pipeline (failed jobs with the last lines of their log), review threads. Full logs: `.logs/<project>/<job>.log`.\n\n'
        jq -r --slurpfile idx "$index" --argjson changed "$changed_json" '
            def cell: tostring | gsub("\\|"; "\\|") | gsub("\n"; " ");
            .[] | "## \(.name) — \(.refs | length)\n\n`\(.query)`\n",
            (if (.refs | length) == 0 then "_none_\n" else
               "| MR | title | branch | pipeline | failed jobs | open threads | updated |\n|---|---|---|---|---|---|---|",
               (.refs[] as $r | ($idx[0][$r] // {}) as $i | ($r | split("!")) as $p
                | "| [\($r)](.mr/\($p[0])/\($p[1]).json)\(if ($changed | index("mr:\($r)")) then " ★" else "" end) "
                  + "| \(if $i.draft then "Draft: " else "" end)\(($i.title // "") | cell) "
                  + "| `\($i.source_branch // "")` → `\($i.target_branch // "")` "
                  + "| \($i.pipeline // "none") "
                  + "| \(($i.failed // []) | join(", ") | cell) "
                  + "| \($i.open_threads // 0) "
                  + "| \(($i.updated // "")[0:10]) |"),
               ""
             end)' "${cache_dir}/queries.json"
    } > "${nav_file}.new"
    mv -- "${nav_file}.new" "$nav_file"
}

# ── Commands ────────────────────────────────────────────────────

cmd_check() {
    prepare
    case "$tls_mode" in
        ca) log "tls: CA + public-key pin" ;;
        pin-only) log "tls: public-key pin" ;;
        *) log "transport: plain http, unencrypted" ;;
    esac
    log "logged in as @${me} with a $([[ "$token_kind" == oauth ]] && printf 'read_api session token (from the password; revoked on exit)' || printf 'personal token (read-only scopes)')"
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
    pull_mrs
    write_navigation_map
    log "pull done: ${#changed[@]} file(s) changed${changed[*]:+ — ${changed[*]}}"

    if [[ "$index" == true ]]; then
        if (( ${#changed[@]} == 0 )); then
            log "nothing changed, graph left as is"
        elif [[ -x "$cbm_script" ]]; then
            "$cbm_script" index "$script_dir" || warn "pull succeeded but re-indexing failed — run: ${cbm_script} index ${script_dir}"
        else
            warn "cannot re-index: ${cbm_script} not found"
        fi
    fi
}

# A link to this server, or a bare "group/project!iid".
parse_link() { # link kind(merge_requests|jobs) -> "path<TAB>id"
    local link="$1" kind="$2"
    if [[ "$link" =~ ^https?://([A-Za-z0-9.-]+)/(.+)/-/${kind}/([0-9]+) ]]; then
        [[ "${BASH_REMATCH[1]}" == "$host" ]] || die "the link points at ${BASH_REMATCH[1]}, not ${host}" "$ex_usage"
        check_path "${BASH_REMATCH[2]}"
        printf '%s\t%s' "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    elif [[ "$kind" == merge_requests && "$link" =~ $ref_pattern ]]; then
        printf '%s\t%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}"
    else
        return 1
    fi
}

cmd_add() {
    local link="${1:-}" parsed path iid ref next
    [[ -n "$link" ]] || die "add: give an MR link or group/project!iid" "$ex_usage"
    require_tools
    load_config
    parsed="$(parse_link "$link" merge_requests)" || die "add: not an MR link (…/<project>/-/merge_requests/<iid>) nor group/project!iid" "$ex_usage"
    IFS=$'\t' read -r path iid <<<"$parsed"
    ref="${path}!${iid}"
    next="$(jq --arg r "$ref" '.merge_requests = ((.merge_requests // []) + [$r] | unique)' "$sources_file")"
    printf '%s\n' "$next" > "${sources_file}.new"
    mv -- "${sources_file}.new" "$sources_file"
    log "${ref} added to sources.json"
    cmd_pull --index
}

cmd_log() {
    local parsed path id
    require_tools
    load_config
    if (( $# == 1 )); then
        parsed="$(parse_link "$1" jobs)" || die "log: not a job link (…/<project>/-/jobs/<id>)" "$ex_usage"
        IFS=$'\t' read -r path id <<<"$parsed"
    elif (( $# == 2 )); then
        path="$1"
        id="$2"
        check_path "$path"
        [[ "$id" =~ ^[0-9]+$ ]] || die "log: job id must be a number" "$ex_usage"
    else
        die "log: give a job link, or <group/project> <job-id>" "$ex_usage"
    fi
    load_tls
    load_credentials
    login
    fetch_log "$path" "$id" || die "log: job ${id} in ${path} has no readable log (erased, or no permission)" "$ex_dataerr"
    printf '%s (%s lines)\n' ".gitlab/.logs/${path}/${id}.log" "$(wc -l < "${logs_dir}/${path}/${id}.log")"
}

cmd_pin() {
    local write=false observed next handshake errors
    [[ "${1:-}" == --write ]] && write=true
    require_tools
    load_config allow-missing-pin
    [[ "$scheme" == https ]] || die "${host} is configured as plain http: no certificate, nothing to pin" "$ex_usage"
    handshake="$(new_tmp)"
    errors="$(new_tmp)"
    timeout 20 openssl s_client -connect "${host}:443" -servername "$host" </dev/null >"$handshake" 2>"$errors" || true
    openssl x509 -noout -in "$handshake" >/dev/null 2>&1 \
        || die "no certificate from ${host}:443 — is the VPN connected? openssl said: $(grep -v '^[[:space:]]*$' "$errors" | head -n 3 | tr '\n' ' ')" "$ex_unavailable"
    observed="sha256//$(openssl x509 -in "$handshake" -pubkey -noout | openssl pkey -pubin -outform der \
        | openssl dgst -sha256 -binary | base64)"
    [[ "$observed" =~ ^sha256//[A-Za-z0-9+/]{43}=$ ]] || die "cannot compute the key pin of ${host}" "$ex_software"
    printf 'configured %s\nobserved   %s%s\n' "${pin:-(none)}" "$observed" \
        "$([[ "$observed" == "$pin" ]] && printf '  (match)' || printf '  (DIFFERENT)')"
    printf 'certificate (compare with the browser):\n  %s\n  %s\n  SHA-256 %s\n' \
        "$(openssl x509 -in "$handshake" -noout -subject)" \
        "$(openssl x509 -in "$handshake" -noout -enddate)" \
        "$(openssl x509 -in "$handshake" -noout -fingerprint -sha256 | cut -d= -f2)"
    if [[ "$write" == true && "$observed" != "$pin" ]]; then
        next="$(jq --arg p "$observed" '.pin = $p' "$sources_file")"
        printf '%s\n' "$next" > "${sources_file}.new"
        mv -- "${sources_file}.new" "$sources_file"
        warn "pin written to sources.json"
    fi
}

main() {
    local command="${1:-help}"
    (( $# > 0 )) && shift
    case "$command" in
        check) cmd_check "$@" ;;
        pull)  cmd_pull "$@" ;;
        add)   cmd_add "$@" ;;
        log)   cmd_log "$@" ;;
        pin)   cmd_pin "$@" ;;
        help|-h|--help) usage ;;
        *) usage >&2; exit "$ex_usage" ;;
    esac
}

main "$@"
