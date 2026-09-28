#!/usr/bin/env bash
# Check which cloned shire-apps repositories (submodules included) use a ROS
# interface with a field whose unit is outside the target system of task 1590
# (SI, temperature in °C, deg and % allowed, time as builtin_interfaces
# Time/Duration, speed in m/s). Pixels are not a physical unit and are ignored.
#
# Usage: ./scripts/check_invalid_units.sh [-r repos-dir] [-q]
#   -r  directory holding the clones (default: <workspace>/jen-shire-app-repos,
#       filled by scripts/clone_shire_app_repos.sh)
#   -q  print only "<repo> true|false", no tables
#
# Exit status: 0 no repository uses an invalid interface, 1 at least one does,
# 2 usage or setup error.
#
# A code file (C/C++/Python) USES an interface when it includes its generated
# header (<pkg>/msg/<snake_name>.hpp), or names the type and the package in the
# same file. A message embedding an invalid one counts as using it too. .msg,
# .srv and .action files never count: a repository that only carries the
# definitions (e.g. as a submodule it builds) VENDORS the interface.
set -euo pipefail

workspace=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly workspace

# unit | package | kind | interface | fields with that unit | messages embedding it
# Source: .claude/projects/jen_calibration_manager/.task_todos/1590_units_invalid.md
readonly invalid_interfaces=(
  'ms (millisecond)|jen_buffer_node_msgs|srv|GetItemByTimestamp|threshold_ms|'
  'ms (millisecond)|jen_hal_msgs|msg|ClocksStatus|clock_diff_ms|'
  'rpm (revolution per minute)|jen_lidar_falcon_driver_msgs|msg|FalconSensorReadings|motor_rpm|FalconStatusExtended'
  'mA (milliampere)|jen_lidar_falcon_driver_msgs|msg|FalconSensorReadings|heater_current_ma|FalconStatusExtended'
  '10 µs (tens of microseconds)|jen_lidar_falcon_driver_msgs|msg|FalconStatusCounters|latency_10us_average latency_10us_variation latency_10us_max|FalconStatusExtended'
  'float64 time, unit undocumented|jen_lidar_falcon_driver_msgs|msg|FalconStatusExtended|timestamp|'
  'float64 time, unit undocumented|jen_lidar_falcon_driver_msgs|msg|FalconStatus|uptime|'
  'km/h (kilometre per hour)|jen_vision_msgs|action|ValidateObject|speed|'
  'km/h (kilometre per hour)|jen_vision_msgs|srv|TriggerEvent|speed|'
  'fraction (0.1 = 10 %)|jen_parameter_msgs|msg|DiagnosticMetricConfig|frequency_tolerance|'
)

readonly code_globs=(
  --include='*.cpp' --include='*.cc' --include='*.cxx' --include='*.c'
  --include='*.hpp' --include='*.hh' --include='*.h' --include='*.ipp' --include='*.py'
)
readonly skipped_dirs=(--exclude-dir=.git --exclude-dir=build --exclude-dir=install
  --exclude-dir=log --exclude-dir=node_modules)

usage() {
  sed -n '7,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

# Code files under $1 matching extended regex $2, one relative path per line.
grep_code() {
  (cd -- "$1" && grep -rIlE "${skipped_dirs[@]}" "${code_globs[@]}" -e "$2" . 2>/dev/null) \
    | sed 's|^\./||' | sort -u || true
}

# FalconStatusExtended -> falcon_status_extended, as rosidl names headers.
snake_case() {
  sed -E 's/([a-z0-9])([A-Z])/\1_\2/g; s/([A-Z])([A-Z][a-z])/\1_\2/g' <<<"$1" | tr '[:upper:]' '[:lower:]'
}

# Code files in repo $1 that use interface $4 of package $2, kind $3.
files_using() {
  local repo_dir=$1 package=$2 kind=$3 name=$4 snake
  snake=$(snake_case "$name")
  {
    grep_code "$repo_dir" "${package}/${kind}/${snake}\\.h"
    comm -12 <(grep_code "$repo_dir" "\\b${name}\\b") \
             <(grep_code "$repo_dir" "\\b${package}(::|/|\\.)")
  } | sort -u
}

# Submodule paths of the repository in $1, recursively, one per line.
submodule_paths() {
  git -C "$1" submodule status --recursive 2>/dev/null | awk '{ print $2 }'
}

# True when path $1 lies inside one of the newline-separated paths in $2.
in_submodule() {
  local file=$1 path
  while IFS= read -r path; do
    [[ -n $path && $file == "$path"/* ]] && return 0
  done <<<"$2"
  return 1
}

# The files in $2 plus their .cpp/.cc siblings, which hold the field accesses
# for a type only named in the header. Prints the fields of $3 found there.
fields_referenced() {
  local repo_dir=$1 files=$2 fields=$3 field file base
  local -a candidates=()
  while IFS= read -r file; do
    [[ -n $file ]] || continue
    candidates+=("$file")
    base=${file%.*}
    [[ -f $repo_dir/$base.cpp ]] && candidates+=("$base.cpp")
    [[ -f $repo_dir/$base.cc ]] && candidates+=("$base.cc")
  done <<<"$files"
  for field in $fields; do
    (cd -- "$repo_dir" && grep -qw -e "$field" -- "${candidates[@]}" 2>/dev/null) \
      && printf '%s\n' "$field"
  done
  return 0
}

# Join lines with ", ", keeping at most $1 entries.
join_limited() {
  sed '/^$/d' | awk -v max="$1" '
    NR <= max { out = out (NR > 1 ? ", " : "") $0 }
    END       { if (NR > max) out = out sprintf(" (+%d more)", NR - max); print out }'
}

main() {
  local repos_dir="$workspace/jen-shire-app-repos" quiet=false option
  while getopts ':r:qh' option; do
    case $option in
      r) repos_dir=$OPTARG ;;
      q) quiet=true ;;
      *) usage ;;
    esac
  done
  shift $((OPTIND - 1))
  (($# == 0)) || usage
  [[ -d $repos_dir ]] || { printf 'error: %s does not exist; run clone_shire_app_repos.sh\n' "$repos_dir" >&2; exit 2; }

  local repo_dir repo spec unit package kind name fields containers container
  local files file own sub where hits submodules any_used=false
  local -a repos=() rows=() verdicts=()
  local -A used=() used_own=() vendored=()

  for repo_dir in "$repos_dir"/*/; do
    [[ -e $repo_dir/.git ]] && repos+=("$(basename -- "$repo_dir")")
  done
  ((${#repos[@]} > 0)) || { printf 'error: no repositories in %s\n' "$repos_dir" >&2; exit 2; }

  for repo in "${repos[@]}"; do
    repo_dir="$repos_dir/$repo"
    submodules=$(submodule_paths "$repo_dir")
    used[$repo]=false
    used_own[$repo]=false
    vendored[$repo]=$(for spec in "${invalid_interfaces[@]}"; do
        IFS='|' read -r _ package kind name _ _ <<<"$spec"
        if [[ -n $(find "$repo_dir" -name .git -prune -o -name "$name.$kind" -print -quit) ]]; then
          printf '%s/%s\n' "$package" "$name"
        fi
      done | sort -u | wc -l)

    for spec in "${invalid_interfaces[@]}"; do
      IFS='|' read -r unit package kind name fields containers <<<"$spec"
      files=$(
        files_using "$repo_dir" "$package" "$kind" "$name"
        for container in $containers; do files_using "$repo_dir" "$package" msg "$container"; done
      )
      files=$(sort -u <<<"$files" | sed '/^$/d')
      [[ -n $files ]] || continue

      own='' sub=''
      while IFS= read -r file; do
        if in_submodule "$file" "$submodules"; then sub+="$file"$'\n'; else own+="$file"$'\n'; fi
      done <<<"$files"
      if [[ -n $own ]]; then where='own code'; used_own[$repo]=true; else where='submodule'; fi
      used[$repo]=true
      any_used=true

      hits=$(fields_referenced "$repo_dir" "$files" "$fields" | sed 's/.*/`&`/' | join_limited 9)
      rows+=("$unit|$repo|$where|$package/$kind/$name|${hits:-— (type only)}|$(printf '%s%s' "$own" "$sub" | join_limited 3)")
    done
    verdicts+=("$repo|${used[$repo]}|${used_own[$repo]}|${vendored[$repo]}")
  done

  if [[ $quiet == true ]]; then
    printf '%s\n' "${verdicts[@]}" | awk -F'|' '{ print $1, $2 }'
  else
    print_report "$repos_dir" "${verdicts[@]}" -- "${rows[@]}"
  fi
  [[ $any_used == false ]]
}

# Markdown: one verdict table, then one table per invalid unit.
print_report() {
  local repos_dir=$1 unit
  shift
  local -a verdicts=() rows=()
  while (($# > 0)) && [[ $1 != -- ]]; do verdicts+=("$1"); shift; done
  shift
  rows=("$@")

  printf '# Invalid-unit interface usage\n\n'
  printf 'Scanned %s repositories in `%s`, submodules included; px ignored.\n\n' \
    "${#verdicts[@]}" "$repos_dir"
  printf '## Verdict\n\n'
  printf '| Repository | Uses invalid interface | In its own code | Invalid interfaces vendored |\n|---|---|---|---|\n'
  printf '%s\n' "${verdicts[@]}" | sort -t'|' -k2,2r -k3,3r -k1,1 | awk -F'|' '
    { printf "| %s | %s | %s | %s |\n", $1, ($2 == "true" ? "**true**" : "false"),
      ($2 == "true" ? ($3 == "true" ? "yes" : "no, submodule only") : "—"), $4 }'

  while IFS= read -r unit; do
    printf '\n## %s\n\n| Repository | Where | Interface | Invalid fields referenced | Files |\n|---|---|---|---|---|\n' "$unit"
    printf '%s\n' "${rows[@]}" | awk -F'|' -v unit="$unit" '
      $1 == unit { n++; printf "| %s | %s | %s | %s | %s |\n", $2, $3, $4, $5, $6 }
      END        { if (!n) print "| — | | not used by any repository | | |" }'
  done < <(printf '%s\n' "${invalid_interfaces[@]}" | cut -d'|' -f1 | awk '!seen[$0]++')
  printf '\n'
}

main "$@"
