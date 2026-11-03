#!/usr/bin/env bash
# Move every first-level submodule of a repository onto the tip of its remote
# branch and stage the new pointers in the parent. Nested submodules are not
# touched, and nothing is committed or pushed.
#
# Usage: ./scripts/rebase_submodules.sh [-b branch] [-r remote] [repo-root]
#   -b  branch to check out and rebase (default: master)
#   -r  remote to fetch and rebase onto (default: origin)
#   repo-root  the parent repository (default: current directory)
#
# For each submodule listed in <repo-root>/.gitmodules:
#   git fetch <remote>; git checkout <branch>; git rebase <remote>/<branch>
# then, in the parent: git add <submodule path>.
#
# A submodule is skipped, and reported, when it is not initialised, has
# uncommitted changes, has no <remote>/<branch>, or its rebase conflicts (the
# rebase is aborted, so it is left as it was). The script carries on with the
# rest and exits 1 if anything was skipped or failed.
set -euo pipefail

usage() {
  sed -n '6,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

log() { printf '%s\n' "$*" >&2; }

# Print the path of every first-level submodule, NUL-terminated.
submodule_paths() {
  local root=$1 entry key path

  git -C "$root" config --file .gitmodules -z --get-regexp '^submodule\..*\.path$' |
    while IFS= read -r -d '' entry; do
      key=${entry%%$'\n'*}
      path=${entry#*$'\n'}
      if [[ -n $key && -n $path ]]; then
        printf '%s\0' "$path"
      fi
    done
}

# Fetch, check out and rebase one submodule; stage it in the parent.
# Returns non-zero, with the reason logged, when the submodule was skipped.
rebase_one() {
  local root=$1 path=$2 branch=$3 remote=$4
  local dir="$root/$path"

  if [[ ! -e $dir/.git ]]; then
    log "  skip: not initialised (git submodule update --init '$path')"
    return 1
  fi
  if [[ -n $(git -C "$dir" status --porcelain --untracked-files=no) ]]; then
    log "  skip: uncommitted changes"
    return 1
  fi

  git -C "$dir" fetch "$remote" || { log "  fail: fetch from '$remote'"; return 1; }

  if ! git -C "$dir" rev-parse --verify --quiet "refs/remotes/$remote/$branch" > /dev/null; then
    log "  skip: no '$remote/$branch'"
    return 1
  fi

  git -C "$dir" checkout "$branch" || { log "  fail: checkout '$branch'"; return 1; }

  if ! git -C "$dir" rebase "$remote/$branch"; then
    git -C "$dir" rebase --abort || true
    log "  fail: rebase onto '$remote/$branch' conflicts; aborted, left on '$branch'"
    return 1
  fi

  git -C "$root" add -- "$path"
  log "  ok: $(git -C "$dir" log -1 --format='%h %s')"
}

main() {
  local branch=master remote=origin root opt
  local -a paths=() failed=()

  while getopts ':b:r:h' opt; do
    case $opt in
      b) branch=$OPTARG ;;
      r) remote=$OPTARG ;;
      *) usage ;;
    esac
  done
  shift $((OPTIND - 1))
  (($# <= 1)) || usage

  root=$(git -C "${1:-.}" rev-parse --show-toplevel 2> /dev/null) ||
    { log "not a git repository: ${1:-.}"; exit 2; }
  [[ -f $root/.gitmodules ]] || { log "no .gitmodules in $root"; exit 0; }

  while IFS= read -r -d '' path; do
    paths+=("$path")
  done < <(submodule_paths "$root")
  ((${#paths[@]} > 0)) || { log "no submodules in $root"; exit 0; }

  for path in "${paths[@]}"; do
    log "== $path"
    rebase_one "$root" "$path" "$branch" "$remote" || failed+=("$path")
  done

  log ""
  log "staged in $root (not committed):"
  git -C "$root" diff --cached --submodule=log -- "${paths[@]}" >&2 || true

  if ((${#failed[@]} > 0)); then
    log "not updated: ${failed[*]}"
    exit 1
  fi
}

main "$@"
