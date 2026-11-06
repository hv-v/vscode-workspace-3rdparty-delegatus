---
trigger: glob
globs:
  - ".gitmodules"
---

# Generated Files

`.gitmodules` is generated from `.gitmodules.t`, not hand-edited. The generator
(`gen-gitmodules.sh`) and `.gitmodules.t` are not present in this checkout, so
confirm with the user how it is regenerated before changing anything. The
`guard-generated` hook (`.agents/hooks.json`) denies a direct edit.
