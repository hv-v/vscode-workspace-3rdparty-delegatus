---
description: Build the jen_calibration_manager runtime Docker image
argument-hint: "[extra docker build flags]"
allowed-tools: Bash(cd:*), Bash(docker build:*), Bash(git submodule:*), Bash(grep:*), Bash(tail:*), Read
---

Build the runtime image for `jen_calibration_manager`. Follow the `build`
skill in this project — Docker only, never `colcon build` on the host.

```bash
cd /home/vhaponov/Documents/jo-workspace/jen_calibration_manager
docker build -t jen_calibration_manager . $ARGUMENTS
```

If it fails, do **not** re-read the truncated BuildKit output — rebuild with
plain progress and report the *first* error:

```bash
docker build --progress=plain -t jen_calibration_manager . $ARGUMENTS > /tmp/build.log 2>&1
grep -n "error:" /tmp/build.log | head
grep -E "Starting >>>|Finished <<<|Failed|Summary:" /tmp/build.log
```

Before concluding it is a code problem, check the two usual causes from the
`build` skill: a new `.cpp` missing from `src/Sources.cmake`, and a
`find_package` without a matching `<depend>` in `package.xml`.

Report: exit status, the `Summary: N packages finished` line, and the first
error with the file and line if the build failed.
