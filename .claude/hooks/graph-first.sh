#!/usr/bin/env bash
# PreToolUse/Bash: refuse a blind recursive text search over a project tree.
#
# rules/code-graph.md says to query the codebase-memory graph first. That is
# guidance the model can skip; this makes it mechanical. Text search stays
# legitimate for what the graph cannot hold (literals, YAML, CMake, docs), so
# the deny names the escape hatch instead of being absolute.
#
# stdin:  PreToolUse hook JSON
# stdout: a deny decision, or nothing
set -euo pipefail

command=$(jq -r '.tool_input.command // ""')
[ -n "$command" ] || exit 0

# Config and docs are not code; searching them is never the graph's job.
if printf '%s' "$command" | grep -qE '(\.claude|templates/|docs/|\.git/)'; then
    exit 0
fi

is_recursive_grep() {
    printf '%s' "$1" | grep -qE '(^|[|;&(]|[[:space:]])(grep|egrep|fgrep)[[:space:]]+(-[[:alnum:]]*[rR])'
}

is_broad_find() {
    printf '%s' "$1" | grep -qE '(^|[|;&(]|[[:space:]])find[[:space:]]+[^|;&]*-(name|iname|path)[[:space:]]'
}

if is_recursive_grep "$command" || is_broad_find "$command"; then
    jq -cn --arg reason \
"Blocked by rules/code-graph.md: query the code graph before a recursive text search. \
Use mcp__codebase-memory__search_graph for a symbol, trace_path for callers, \
get_file_outline for a file's shape, or search_code for literals. \
If text search is genuinely right here (a string literal, YAML, CMake, or a doc), \
scope the command to one directory or add --include, and it will pass." \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
fi
exit 0
