#!/usr/bin/env bash
# Create a new skill for a project from a template, substituting the mechanical
# placeholders. To install an already-filled skill, use install-skill.sh.
#
#   new-skill.sh <type> <project-path> [skill-name] [--force]
#
#   new-skill.sh build jen_plate_reader          # relative to cwd or workspace
#   new-skill.sh build ../other-repo             # relative
#   new-skill.sh build /abs/path/to/repo         # absolute
#   new-skill.sh build jen_plate_reader hil-build   # rename the skill
#
# <project-path> resolves as: as given, then relative to the workspace root.
# The skill is written to
#   <workspace>/.claude/projects/<project root dir name>/.claude/skills/<name>
# - never inside the project repo, whose history is its own.
# Refuses to overwrite an existing skill unless --force.
set -euo pipefail

TEMPLATES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../claude-templates/skills-t
# shellcheck source=_lib.sh
. "$TEMPLATES/_lib.sh"

WS="$(workspace_root "$TEMPLATES")" ||
    die "no workspace root above $TEMPLATES (looked for a .claude/ directory)"

usage() {
  echo "usage: $(basename "$0") <type> <project-path> [skill-name] [--force]" >&2
  echo "  type: $(template_types)" >&2
  exit 2
}

FORCE=0; POS=()
for a in "$@"; do
  case "$a" in
    --force) FORCE=1 ;;
    -*)      usage ;;
    *)       POS+=("$a") ;;
  esac
done
[ ${#POS[@]} -ge 2 ] && [ ${#POS[@]} -le 3 ] || usage

TYPE=${POS[0]}
RAW=${POS[1]}
NAME=${POS[2]:-$TYPE}

[ -f "$TEMPLATES/$TYPE/SKILL.md" ] || { echo "no template '$TYPE'" >&2; usage; }
[[ "$NAME" =~ ^[a-z0-9-]+$ ]] || die "skill name must be [a-z0-9-]: '$NAME'"

# The project directory must exist: its name is the key the skill is filed
# under, so a typo would silently create a second, orphaned project entry.
PROJ_DIR="$(resolve_dir "$RAW" "$WS")" ||
  die "no such project directory: '$RAW' (tried cwd and $WS)"
warn_outside_workspace "$WS" "$PROJ_DIR"

PROJ="$(basename "$PROJ_DIR")"
SKILLS_DIR="$(project_skills_dir "$WS" "$PROJ_DIR")"
DST="$SKILLS_DIR/$NAME"
if [ -e "$DST" ] || [ -L "$DST" ]; then
  [ "$FORCE" = 1 ] || die "$DST exists (pass --force to replace)"
  rm -rf "$DST"
fi

mkdir -p "$SKILLS_DIR"
cp -r "$TEMPLATES/$TYPE" "$DST"

# Mechanical substitutions only; everything else is yours to write.
find "$DST" -type f \( -name '*.md' -o -name '*.yaml' -o -name '*.yml' -o -name '*.py' \) \
  -exec sed -i -e "s/{{PROJECT}}/$PROJ/g" -e "s/{{PACKAGE}}/$PROJ/g" -e "s/{{IMAGE}}/$PROJ/g" {} +

# The frontmatter name must equal the directory name.
if [ "$NAME" != "$TYPE" ]; then
  sed -i "0,/^name: $TYPE$/s//name: $NAME/" "$DST/SKILL.md"
fi

echo "created $DST"
echo "next:  read $TEMPLATES/HOW-TO-FILL.md, then fill it in"
echo "       query the code graph (mcp__codebase-memory__*) for $PROJ before you write"
echo "done when:  grep -rn '{{\\|<!--' $DST   comes back empty"
