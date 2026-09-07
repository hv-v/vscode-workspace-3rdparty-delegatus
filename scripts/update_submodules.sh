#!/usr/bin/env bash
# Usage: ./scripts/update_submodules.sh [folder-containing-repositories]
set -euo pipefail

for repo in "${1:-.}"/*/; do
  [[ -e "$repo/.git" ]] || continue
  printf 'Updating submodules: %s\n' "$repo"
  git -C "$repo" submodule update --init --recursive
done
