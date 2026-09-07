#!/usr/bin/env bash
# PostToolUse/Write|Edit: format a C++ file with the owning repo's own style.
#
# The style file is authoritative for layout (see the a-verify-cpp precedence
# list), so this only ever applies a rule the repo already states. A repo with
# no .clang-format is left alone rather than guessed at.
#
# stdin:  PostToolUse hook JSON
# stdout: nothing on success
set -euo pipefail

command -v clang-format >/dev/null 2>&1 || exit 0

file_path=$(jq -r '.tool_response.filePath // .tool_input.file_path // ""')
[ -n "$file_path" ] && [ -f "$file_path" ] || exit 0

case "$file_path" in
    *.cpp|*.hpp|*.h|*.cc|*.cxx|*.hh) ;;
    *) exit 0 ;;
esac

# Walk up for the nearest .clang-format; the repo that owns the file owns its
# layout, and this workspace holds several repos with their own styles.
find_style_file() {
    local dir
    dir=$(cd "$(dirname "$1")" && pwd)
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/.clang-format" ]; then
            printf '%s' "$dir/.clang-format"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    return 1
}

style_file=$(find_style_file "$file_path") || exit 0
clang-format -i --style=file:"$style_file" "$file_path"
exit 0
