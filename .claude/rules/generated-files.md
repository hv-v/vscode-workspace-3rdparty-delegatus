---
paths:
  - ".gitmodules"
  - ".gitmodules.t"
  - ".gitparams"
  - "gen-gitmodules.sh"
---

# Generated files

`.gitmodules` is generated, not tracked — `./gen-gitmodules.sh` renders it from
the tracked `.gitmodules.t` plus the ignored `.gitparams`. Regenerate after a
fresh clone or any submodule change; never hand-edit `.gitmodules`.
