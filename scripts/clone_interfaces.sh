#!/usr/bin/env bash
# Usage: ./scripts/clone_interfaces.sh [destination-directory]
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/jo-interface-repo-list.sh"
mkdir -p -- "${1:-.}"
cd -- "${1:-.}"
for repo in "${repos[@]}"; do
  directory=${repo##*/}
  [[ -e ${directory%.git} ]] || git clone -- "$repo"
done
