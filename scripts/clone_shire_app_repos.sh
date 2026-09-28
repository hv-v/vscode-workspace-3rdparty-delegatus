#!/usr/bin/env bash
# Clone every application repository deployed by the shire-apps umbrella charts,
# with all submodules.
#
# Usage: ./scripts/clone_shire_app_repos.sh [-a shire-apps-dir] [-d destination] [-u]
#   -a  shire-apps checkout (default: <workspace>/shire-apps; cloned if absent)
#   -d  where the repositories go (default: <workspace>/jen-shire-app-repos)
#   -u  also fetch and fast-forward repositories that are already cloned
#
# The repository of each chart is the `home:` field of the Chart.yaml packed in
# shire-*/charts/<chart>-<version>.tgz (run `helm dependency update` to get
# them). A dependency without a packed chart falls back to
# shire/<chart name with - replaced by _>. Chart repositories (shire/charts/*)
# are skipped: they hold no code.
set -euo pipefail

readonly git_host='git@as-git-01.jenoptik.corp'
readonly shire_apps_url="${git_host}:shire/charts/shire-apps.git"
workspace=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly workspace

usage() {
  sed -n '5,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

log() { printf '%s\n' "$*" >&2; }

# Print "<repo path on the git host>" for every chart dependency, one per line.
list_repo_paths() {
  local shire_apps=$1 umbrella chart_tgz home name

  for chart_tgz in "$shire_apps"/shire-*/charts/*.tgz; do
    [[ -e $chart_tgz ]] || continue
    # Only the top-level Chart.yaml; nested ones are the chart's own deps.
    home=$(tar -xzOf "$chart_tgz" --wildcards --no-wildcards-match-slash \
      '*/Chart.yaml' 2>/dev/null | sed -n 's/^home:[[:space:]]*//p' | head -n1)
    home=${home%/}
    [[ -n $home ]] && printf '%s\n' "${home#*://*/}"
  done

  # Fallback for dependencies that were never fetched with helm.
  for umbrella in "$shire_apps"/shire-*/Chart.yaml; do
    while read -r name; do
      [[ -n $(compgen -G "$shire_apps/shire-*/charts/${name}-[0-9]*.tgz") ]] \
        && continue
      printf 'shire/%s\n' "${name//-/_}"
    done < <(dependency_names "$umbrella")
  done
}

# Names of the non-local dependencies declared in one Chart.yaml.
dependency_names() {
  awk '
    /^[^[:space:]#]/      { in_deps = ($1 == "dependencies:") ; next }
    !in_deps              { next }
    /^[[:space:]]*-[[:space:]]*name:/ { flush(); sub(/.*name:[[:space:]]*/, ""); name = $0; next }
    /repository:.*file:\/\// { name = "" }
    function flush() { if (name != "") print name; name = "" }
    END                   { flush() }
  ' "$1" | tr -d '"'"'"
}

# Clone one repository with submodules, or update it with -u.
clone_repo() {
  local repo_path=$1 destination=$2 update=$3 directory status=0

  directory="$destination/${repo_path##*/}"
  if [[ -e $directory/.git ]]; then
    if [[ $update == true ]]; then
      log "update  $repo_path"
      git -C "$directory" pull --ff-only --quiet || status=$?
    else
      log "exists  $repo_path"
    fi
  else
    log "clone   $repo_path"
    git clone --quiet -- "${git_host}:${repo_path}.git" "$directory" || return 1
  fi

  update_submodules "$directory" || status=1
  return "$status"
}

# Init submodules one at a time, recursively. `update --init --recursive` aborts
# on the first unreachable submodule and leaves the rest at the wrong commit;
# some submodules here are access-restricted, so fetch what is reachable.
update_submodules() {
  local directory=$1 key path status=0

  [[ -f $directory/.gitmodules ]] || return 0
  while read -r key path; do
    if git -C "$directory" submodule update --init --quiet -- "$path" 2>/dev/null; then
      update_submodules "$directory/$path" || status=1
    else
      log "warning: cannot fetch submodule $directory/$path"
      status=1
    fi
  done < <(git config -f "$directory/.gitmodules" --get-regexp '^submodule\..*\.path$')
  return "$status"
}

main() {
  local shire_apps="$workspace/shire-apps" destination="$workspace/jen-shire-app-repos"
  local update=false option repo_path
  local -a failed=() repo_paths=()

  while getopts ':a:d:uh' option; do
    case $option in
      a) shire_apps=$OPTARG ;;
      d) destination=$OPTARG ;;
      u) update=true ;;
      *) usage ;;
    esac
  done
  shift $((OPTIND - 1))
  (($# == 0)) || usage

  if [[ ! -d $shire_apps ]]; then
    log "clone   shire-apps -> $shire_apps"
    git clone --quiet -- "$shire_apps_url" "$shire_apps"
  fi
  if [[ -z $(compgen -G "$shire_apps/shire-*/charts/*.tgz") ]]; then
    log "warning: no packed charts in $shire_apps; run 'helm dependency update'" \
      "for accurate repository URLs. Guessing them from chart names."
  fi

  mapfile -t repo_paths < <(list_repo_paths "$shire_apps" | grep -v '^shire/charts/' | sort -u)
  ((${#repo_paths[@]} > 0)) || { log "error: no repositories found"; exit 1; }

  mkdir -p -- "$destination"
  for repo_path in "${repo_paths[@]}"; do
    clone_repo "$repo_path" "$destination" "$update" || failed+=("$repo_path")
  done

  log ""
  log "${#repo_paths[@]} repositories in $destination"
  if ((${#failed[@]} > 0)); then
    log "incomplete (clone or submodule failure):"
    printf '  %s\n' "${failed[@]}" >&2
    exit 1
  fi
}

main "$@"
