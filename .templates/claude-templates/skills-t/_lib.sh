#!/usr/bin/env bash
# Shared helpers for new-skill.sh and install-skill.sh. Sourced, not executed.

EXCLUDE_LINE='.claude/**'

die() { echo "error: $*" >&2; exit 1; }

# workspace_root <start-dir>
# Echoes the nearest ancestor containing .claude/. Walking up beats assuming a
# fixed depth: this tree has already moved once, and a wrong root silently
# breaks workspace-relative path resolution instead of erroring.
workspace_root() {
    local dir=$1
    while [ "$dir" != "/" ] && [ -n "$dir" ]; do
        if [ -d "$dir/.claude" ]; then
            printf '%s' "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    return 1
}

# resolve_dir <raw-path> [fallback-base ...]
# Echoes the absolute path of the first hit: <raw> as given (absolute or
# relative to cwd), then <base>/<raw> for each base in order. Returns 1 if none.
resolve_dir() {
  local raw=$1 base
  shift
  if [ -d "$raw" ]; then (cd "$raw" && pwd); return 0; fi
  for base in "$@"; do
    if [ -d "$base/$raw" ]; then (cd "$base/$raw" && pwd); return 0; fi
  done
  return 1
}

# git_exclude <project-dir>
# Locally ignore .claude/ in that repo. Never creates the file, never touches
# the tracked .gitignore, never duplicates the line.
git_exclude() {
  local proj_dir=$1 dot="$1/.git" gitdir exclude

  if [ -d "$dot" ]; then
    gitdir="$dot"
  elif [ -f "$dot" ]; then                       # submodule / worktree pointer
    gitdir="$(sed -n 's/^gitdir: //p' "$dot")"
    case "$gitdir" in /*) ;; *) gitdir="$proj_dir/$gitdir" ;; esac
  else
    return 0                                     # not a repo root - nothing to do
  fi

  exclude="$gitdir/info/exclude"
  [ -f "$exclude" ] || return 0                  # only if it already exists
  grep -qxF "$EXCLUDE_LINE" "$exclude" && return 0

  # Keep a trailing newline before appending, in case the file lacks one.
  if [ -s "$exclude" ] && [ -n "$(tail -c1 "$exclude")" ]; then echo >> "$exclude"; fi
  printf '%s\n' "$EXCLUDE_LINE" >> "$exclude"
  echo "excluded: added '$EXCLUDE_LINE' to $exclude"
}

# template_types -> space-separated list of template directory names
template_types() {
  local d
  for d in "$TEMPLATES"/*/; do
    [ -f "$d/SKILL.md" ] && basename "$d"
  done | tr '\n' ' '
}
