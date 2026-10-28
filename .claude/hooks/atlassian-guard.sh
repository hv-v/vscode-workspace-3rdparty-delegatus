#!/usr/bin/env bash
# PreToolUse/Bash|WebFetch: corporate Atlassian hosts are reached only from
# this machine, only through .atlassian/sync.sh, and so only with GET.
#
# WebFetch is also denied by permissions in settings.json; this covers the
# Bash side — a hand-written curl/wget could send a POST or leak the password,
# sync.sh cannot. A bare sync.sh invocation passes even when it carries a link
# (`sync.sh add '<confluence link>'`), as long as nothing is chained to it.
#
# stdin:  PreToolUse hook JSON
# stdout: a deny decision, or nothing
set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat) || exit 0

target=$(jq -r '
    if .tool_name == "WebFetch" then .tool_input.url // ""
    elif .tool_name == "Bash" then .tool_input.command // ""
    else "" end' <<<"$payload" 2>/dev/null) || exit 0

# The real credentials file is the user's alone; the .example placeholder is not.
if [[ "$(jq -r '.tool_name' <<<"$payload")" == Bash ]] \
    && printf '%s' "$target" | grep -qE '\.secrets/+(credentials($|[^.])|[*?[{])'; then
    jq -cn --arg reason \
"Blocked: .atlassian/.secrets/credentials holds the user's password and is theirs alone — never read, \
print, copy or edit it. To test the login run '.atlassian/sync.sh check'; to change it, ask the user." \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
    exit 0
fi

printf '%s' "$target" | grep -qiE 'jenoptik\.corp' || exit 0

# sync.sh alone: no ; | & $ ` < > or newline that could smuggle in another command.
if [[ "$(jq -r '.tool_name' <<<"$payload")" == Bash ]] \
    && printf '%s' "$target" | grep -qE '^[[:space:]]*([^[:space:];|&$`<>]*/)?\.atlassian/sync\.sh([[:space:]][^;|&$`<>]*)?$' \
    && [[ "$target" != *$'\n'* ]]; then
    exit 0
fi

jq -cn --arg reason \
"Blocked by .atlassian/README.md: Jira and Confluence are reached only through .atlassian/sync.sh, \
which is GET-only, pins the servers' keys and keeps the password off the command line. \
Run '.atlassian/sync.sh check' to test access, '.atlassian/sync.sh pull --index' to refresh, \
or '.atlassian/sync.sh add <link>' for a new page or issue (run it alone, nothing chained), and read the mirror under .atlassian/.jira and .atlassian/.confluence." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
exit 0
