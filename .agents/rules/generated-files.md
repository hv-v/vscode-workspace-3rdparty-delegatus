---
trigger: glob
globs:
  - ".gitmodules"
  - ".gitmodules.t"
  - ".gitparams"
  - "gen-gitmodules.sh"
---

# Generated Files

`.gitmodules` is generated, not tracked directly. `./gen-gitmodules.sh` renders it from tracked `.gitmodules.t` and ignored `.gitparams`.
Never hand-edit `.gitmodules`; regenerate with `./gen-gitmodules.sh`.
