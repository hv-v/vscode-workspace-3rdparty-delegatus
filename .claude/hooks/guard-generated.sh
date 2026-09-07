#!/usr/bin/env bash
# PreToolUse/Write|Edit: refuse a hand-edit of a generated file.
#
# rules/generated-files.md records .gitmodules as generated. The generator named
# there is not present in this checkout, so the deny says so rather than sending
# anyone to run a script that does not exist.
#
# stdin:  PreToolUse hook JSON
# stdout: a deny decision, or nothing
set -euo pipefail

file_path=$(jq -r '.tool_input.file_path // ""')
[ -n "$file_path" ] || exit 0

case "$(basename "$file_path")" in
    .gitmodules)
        jq -cn --arg reason \
"Blocked by rules/generated-files.md: .gitmodules is generated from .gitmodules.t, not hand-edited. \
Note that gen-gitmodules.sh and .gitmodules.t are not present in this checkout, \
so confirm with the user how it is regenerated before changing anything here." \
            '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
        ;;
esac
exit 0
