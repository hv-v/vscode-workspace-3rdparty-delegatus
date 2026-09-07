#!/usr/bin/env bash
# Shared helpers for new-skill.sh and install-skill.sh. Sourced, not executed.

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

# project_skills_dir <workspace-root> <project-dir>
# Echoes where this project's skills live:
#   <ws>/.claude/projects/<project root directory name>/.claude/skills
# The directory name under .claude/projects/ is always the project's own root
# directory name, spelled identically - that mapping is how a project's
# configuration is found, so it is derived here and never passed in.
# Nothing is ever written inside the project repo.
project_skills_dir() {
  local ws=$1 proj_dir=$2
  printf '%s/.claude/projects/%s/.claude/skills' "$ws" "$(basename "$proj_dir")"
}

# warn_outside_workspace <workspace-root> <project-dir>
# A repo outside the workspace still gets a .claude/projects/<name> entry here,
# but the name is then no longer unique by construction - say so once.
warn_outside_workspace() {
  local ws=$1 proj_dir=$2
  case "$proj_dir" in
    "$ws"/*) return 0 ;;
  esac
  echo "note: $proj_dir is outside $ws - its skills still land in .claude/projects/$(basename "$proj_dir")" >&2
}

# template_types -> space-separated list of template directory names
template_types() {
  local d
  for d in "$TEMPLATES"/*/; do
    [ -f "$d/SKILL.md" ] && basename "$d"
  done | tr '\n' ' '
}
