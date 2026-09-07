---
description: Rebuild jen_calibration_manager with plain progress and triage the first compiler error
argument-hint: "[image|tester]"
allowed-tools: Bash(cd:*), Bash(docker build:*), Bash(grep:*), Bash(sed:*), Bash(tail:*), Read, Edit
---

Full-output rebuild of `jen_calibration_manager` for error triage. Target
from $ARGUMENTS — `tester` for the test stage, anything else (or empty) for
the runtime image.

```bash
cd /home/vhaponov/Documents/jo-workspace/jen_calibration_manager
docker build --progress=plain -t jen_calibration_manager . > /tmp/build.log 2>&1   # or:
docker build --progress=plain --target tester -t jen_calibration_manager_build:latest . > /tmp/build.log 2>&1
```

Then triage in this order and report what you find:

1. `grep -n "error:" /tmp/build.log | head` — the **first** error only; later
   ones are usually fallout.
2. `grep -E "Starting >>>|Finished <<<|Failed|Summary:" /tmp/build.log` — did
   every expected package build?
3. Match the error against the catalogue in the `build` skill (missing
   `<depend>`, missing entry in `src/Sources.cmake`, missing generated
   `jen_parameter_msgs` header, unpopulated submodule).

Fix the cause rather than the symptom, then rebuild to confirm.
