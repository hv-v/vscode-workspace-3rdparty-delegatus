#!/usr/bin/env bash
# PreToolUse/Bash|WebFetch: corporate hosts (*.jenoptik.corp — Jira,
# Confluence, GitLab) are reached only from this machine, and only through
# the mirror scripts, which are read-only and keep secrets off the command line:
#   .atlassian/sync.sh   Jira and Confluence
#   .gitlab/sync.sh      GitLab merge requests, pipelines, job logs
# Plain git over SSH (git@<host>:group/repo.git) also passes: that is the
# user's ordinary clone/fetch/push route, and it carries no password.
#
# The credentials check also covers file tools (Read, Write, Edit) when a
# harness routes them here — Antigravity does, through .agents/hooks/; Claude
# Code relies on the Read deny in settings.json for that.
#
# WebFetch is also denied by permissions in settings.json; this covers the
# Bash side — a hand-written curl/wget could send a POST or leak a password,
# the scripts cannot. A bare script call passes even when it carries a link
# (`sync.sh add '<link>'`), as long as nothing is chained to it.
#
# stdin:  PreToolUse hook JSON
# stdout: a deny decision, or nothing
set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat) || exit 0

tool=$(jq -r '.tool_name // ""' <<<"$payload" 2>/dev/null) || exit 0
target=$(jq -r '
    if .tool_name == "WebFetch" then .tool_input.url // ""
    elif .tool_name == "Bash" then .tool_input.command // ""
    elif .tool_name == "Read" or .tool_name == "Write" or .tool_name == "Edit" then .tool_input.file_path // ""
    else "" end' <<<"$payload" 2>/dev/null) || exit 0

deny() {
    jq -cn --arg reason "$1" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
    exit 0
}

# The real credentials files are the user's alone; the .example placeholders are not.
if [[ "$tool" != WebFetch ]] \
    && printf '%s' "$target" | grep -qE '\.secrets/+(credentials($|[^.])|[*?[{])'; then
    deny "Blocked: .atlassian/.secrets/credentials and .gitlab/.secrets/credentials hold the user's \
password and are theirs alone — never read, print, copy or edit them. To test a login run \
'.atlassian/sync.sh check' or '.gitlab/sync.sh check'; to change one, ask the user."
fi

[[ "$tool" == Bash || "$tool" == WebFetch ]] || exit 0
printf '%s' "$target" | grep -qiE 'jenoptik\.corp' || exit 0

if [[ "$tool" == Bash && "$target" != *$'\n'* ]]; then
    # A mirror script alone: no ; | & $ ` < > that could smuggle in another command.
    if printf '%s' "$target" \
        | grep -qE '^[[:space:]]*([^[:space:];|&$`<>]*/)?\.(atlassian|gitlab)/sync\.sh([[:space:]][^;|&$`<>]*)?$'; then
        exit 0
    fi
    # git alone, where every corporate host appears as an SSH remote.
    if printf '%s' "$target" | grep -qE '^[[:space:]]*git[[:space:]][^;|&$`<>]*$' \
        && ! printf '%s' "$target" \
            | sed -E 's#(ssh://)?git@[A-Za-z0-9.-]+\.jenoptik\.corp[:/]##g' \
            | grep -qiE 'jenoptik\.corp'; then
        exit 0
    fi
fi

deny "Blocked by .atlassian/README.md and .gitlab/README.md: corporate hosts are reached only \
through the read-only mirror scripts, which pin the servers' keys and keep secrets off the command \
line. Jira/Confluence: '.atlassian/sync.sh check | pull --index | add <link>'. GitLab: \
'.gitlab/sync.sh check | pull --index | add <MR link> | log <job link>'. Run the script alone, \
nothing chained, then read the mirror files. Plain 'git' over SSH (git@host:repo) is allowed."
