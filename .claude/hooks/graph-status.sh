#!/usr/bin/env bash
# SessionStart: name the project directories that have no code graph yet.
#
# An unindexed project is the one case where the graph-first rule cannot be
# followed, and it is invisible until a query comes back empty mid-task. Say it
# once, at the start, with the command that fixes it.
#
# stdin:  SessionStart hook JSON (unused)
# stdout: additionalContext + a user-visible systemMessage, or nothing
set -euo pipefail

workspace=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$workspace"

# Never delay a session start on docker: no answer means say nothing.
indexed=$(timeout 8 ./docker/cbm/cbm.sh tool list_projects '{}' 2>/dev/null) || exit 0
[ -n "$indexed" ] || exit 0

missing=()
for dir in */; do
    project=${dir%/}
    # Only real repos: a project root here holds a .git file or directory.
    [ -e "$project/.git" ] || continue
    if ! printf '%s' "$indexed" | grep -q -- "-${project}\( \|$\)"; then
        missing+=("$project")
    fi
done

[ ${#missing[@]} -gt 0 ] || exit 0

list=$(printf '%s, ' "${missing[@]}"); list=${list%, }
message="Not in the code graph: ${list}. Index with ./docker/cbm/cbm.sh index <project> before asking structural questions about them."

jq -cn --arg msg "$message" \
    '{systemMessage:$msg,hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$msg}}'
exit 0
