#!/usr/bin/env bash
# Install an EXISTING (already filled in) skill into a project, or machine-wide.
#
#   install-skill.sh <skill> <target> [--link] [--force] [--no-exclude]
#
#   install-skill.sh jen_calibration_manager/.claude/skills/deploy jen_plate_reader
#   install-skill.sh ./deploy /abs/path/to/repo --force
#   install-skill.sh .claude/skills/build --global --link
#
# <skill>        a directory containing SKILL.md. Resolved as given, then
#                relative to the workspace root, then as a template name - and
#                a template is handed off to new-skill.sh, which fills in the
#                placeholders instead of refusing them.
# <target>       a project directory (full or relative), or --global for
#                ~/.claude/skills (loads in every session, any cwd)
# --link         symlink instead of copy, so edits stay in one place
# --force        replace an existing skill of that name
# --no-exclude   skip the .git/info/exclude update
#
# After installing into a project, '.claude/**' is appended to that repo's
# .git/info/exclude so the skills are ignored locally without touching the
# tracked .gitignore. Only ever appends, and only if that file already exists.
set -euo pipefail

TEMPLATES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../claude-templates/skills-t
WS="$(cd "$TEMPLATES/../.." && pwd)"                        # workspace root
# shellcheck source=_lib.sh
. "$TEMPLATES/_lib.sh"

usage() {
  echo "usage: $(basename "$0") <skill> <target|--global> [--link] [--force] [--no-exclude]" >&2
  echo "  skill: a path to a skill directory, or a template name ($(template_types))" >&2
  exit 2
}

LINK=0; FORCE=0; NO_EXCLUDE=0; POS=()
for a in "$@"; do
  case "$a" in
    --link)       LINK=1 ;;
    --force)      FORCE=1 ;;
    --no-exclude) NO_EXCLUDE=1 ;;
    --global)     POS+=("$a") ;;
    -*)           usage ;;
    *)            POS+=("$a") ;;
  esac
done
[ ${#POS[@]} -eq 2 ] || usage
SRC_RAW=${POS[0]}; TARGET_RAW=${POS[1]}

# Resolve the source skill: as given, then under the workspace, then as a
# template name.
SRC="$(resolve_dir "$SRC_RAW" "$WS" "$TEMPLATES")" ||
  die "no such skill directory: '$SRC_RAW' (also not a template: $(template_types))"
[ -f "$SRC/SKILL.md" ] || die "$SRC has no SKILL.md - not a skill"

# A template is not something to install as-is: hand it to new-skill.sh, which
# substitutes the placeholders. That is what `install-skill.sh build <proj>` means.
case "$SRC" in
  "$TEMPLATES"/*)
    TYPE="$(basename "$SRC")"
    [ "$TARGET_RAW" = "--global" ] &&
      die "'$TYPE' is a template - it must be filled in for a project before going global"
    [ "$LINK" = 1 ] &&
      die "'$TYPE' is a template - --link would share one unfilled skill across projects"
    echo "note: '$TYPE' is a template - creating a new skill via new-skill.sh"
    ARGS=("$TYPE" "$TARGET_RAW")
    [ "$FORCE" = 1 ]      && ARGS+=(--force)
    [ "$NO_EXCLUDE" = 1 ] && ARGS+=(--no-exclude)
    exec "$TEMPLATES/new-skill.sh" "${ARGS[@]}"
    ;;
esac

NAME="$(basename "$SRC")"
[[ "$NAME" =~ ^[a-z0-9-]+$ ]] || die "skill dir name must be [a-z0-9-]: '$NAME'"

# Refuse to ship a half-written skill.
if grep -rq '{{' "$SRC"; then
  echo "unfilled placeholders in $SRC:" >&2
  grep -rn '{{' "$SRC" | head >&2
  die "fill them in first (see $TEMPLATES/HOW-TO-FILL.md)"
fi

# Resolve the target skills directory.
PROJ_DIR=""
if [ "$TARGET_RAW" = "--global" ]; then
  SKILLS_DIR="$HOME/.claude/skills"
else
  PROJ_DIR="$(resolve_dir "$TARGET_RAW" "$WS")" ||
    die "no such target directory: '$TARGET_RAW'"
  SKILLS_DIR="$PROJ_DIR/.claude/skills"
fi

DST="$SKILLS_DIR/$NAME"
[ "$SRC" = "$DST" ] && die "source and target are the same"

if [ -e "$DST" ] || [ -L "$DST" ]; then
  [ "$FORCE" = 1 ] || die "$DST exists (pass --force to replace)"
  rm -rf "$DST"
fi

mkdir -p "$SKILLS_DIR"
if [ "$LINK" = 1 ]; then
  ln -s "$SRC" "$DST"; echo "linked $DST -> $SRC"
else
  cp -r "$SRC" "$DST"; echo "copied $SRC -> $DST"
fi

if [ -n "$PROJ_DIR" ] && [ "$NO_EXCLUDE" = 0 ]; then
  git_exclude "$PROJ_DIR"
fi

# A copied skill usually names another project; a link deliberately does not.
if [ "$LINK" = 0 ] && [ -n "$PROJ_DIR" ]; then
  echo "note: review the description and any project names in $DST/SKILL.md"
fi
# Same name from two sources shadows; which wins depends on the session cwd.
if [ -e "$HOME/.claude/skills/$NAME" ] && [ -n "$PROJ_DIR" ]; then
  echo "note: '$NAME' also exists in ~/.claude/skills - they shadow each other; keep the descriptions distinct"
fi
exit 0
