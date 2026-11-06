---
name: build
description: Build the jen_calibration_manager Docker images (runtime and tester) and diagnose its colcon / CMake / rosidl / submodule build failures. Use when asked to build, compile, rebuild or produce an image for jen_calibration_manager, when adding a source file, message or dependency to it, or when a build error in this repo needs triage.
---

# Build jen_calibration_manager

Project-specific build workflow. The migrated workspace `p-build` is an
unimplemented stub; this skill contains the project procedure.

Docker only — the ROS Jazzy toolchain and the Jenoptik packages exist solely
inside `nexus-hil.group.jenoptik.corp:8082/ros:jazzy`. **Nothing in this
package compiles standalone on the host any more**: every header reaches
`CalibrationTypes.hpp`, which needs the rosidl-generated
`jen_parameter_msgs` headers that only exist after a real colcon build.

```bash
WS=/home/vhaponov/Documents/jo-workspace
cd "$WS/jen_calibration_manager"
```

## The two images

| target | tag used here | contents |
|---|---|---|
| (default) | `jen_calibration_manager` | runtime image, `ros2 run` ready — used by the `deploy` skill |
| `tester` | `jen_calibration_manager_build:latest` | build tree + gtests + `/ros2_ws/gcov` — used by the `tester` skill |

```bash
docker build -t jen_calibration_manager .                                   # ~90s warm
docker build --target tester -t jen_calibration_manager_build:latest .      # ~25s warm
```

**The default build never runs the tests.** The final stage copies from
`builder`, not from `tester` (`Dockerfile:54`), so the test stage is not part
of that graph at all - `docker build -t jen_calibration_manager .` can succeed
with broken tests. Run the `tester` target explicitly, and force it to
re-execute with `--no-cache-filter tester` when nothing in the context
changed, or every layer comes back `CACHED` and nothing runs.

On failure, rebuild with plain progress — BuildKit hides the *first* error,
which is the one that matters:

```bash
docker build --progress=plain -t jen_calibration_manager . > /tmp/build.log 2>&1
grep -n "error:" /tmp/build.log | head
grep -E "Starting >>>|Finished <<<|Failed|Summary:" /tmp/build.log
```

`Summary: 6 packages finished` is the healthy line for this repo
(`jen_logging`, `jen_py_logging`, `jen_parameter_msgs`, `jen_parameter_utils`,
`jen_config_manager_interface`/`_lib_cpp`, `jen_calibration_manager_msgs`,
`jen_calibration_manager` — the count moves when submodules change).

## Prerequisites

```bash
getent hosts nexus-hil.group.jenoptik.corp
git submodule update --init --recursive
```

Three submodules are `COPY`d into the image and must be populated:
`jen_logging`, `jen_calibration_manager_msgs`, `jen_config_manager_msgs`.

## What to touch when adding code

- **A new `.cpp` in `src/`** → add it to `src/Sources.cmake`. Symptom if you
  forget: `undefined reference` at link time, never a missing-file error.
  Same for `test/Sources.cmake` and a new `*Test.cpp`.
- **A new `find_package(X REQUIRED)` in `CMakeLists.txt`** → add a matching
  `<depend>X</depend>` to `package.xml`. `scripts/build.sh` runs
  `colcon build --packages-up-to jen_calibration_manager`, and
  `--packages-up-to` derives the build set from `package.xml` only. A package
  missing there is never built, so its generated headers never get installed.
- **A new service/message for this node** → `jen_calibration_manager_msgs`
  (`srv/SetTransformation.srv` is the existing example); it is already wired
  for `rosidl_generate_interfaces` with a `geometry_msgs` dependency.
- **A new config-manager-carried message type** → lives in the
  `jen_config_manager_msgs` submodule under
  `jen_parameter_msgs/msg/Calibration/` and must be listed in
  `jen_parameter_msgs/msg/Sources.cmake` (`CONFIG_MANAGER_TYPE_MESSAGES`).
  That is where `JenTFMessage`, `JenCameraInfo` and `JenCameraInfoPair` are;
  `include/CalibrationTypes.hpp` only aliases them.

## Error catalogue

**`Could not find a package configuration file provided by "jen_parameter_msgs"`**
and **`fatal error: jen_parameter_msgs/msg/jen_tf_message.hpp: No such file`**
are the same root cause: the package is `find_package`d but not `<depend>`ed,
so `--packages-up-to` skipped it. Fix `package.xml`; do not chase include
paths. The current list that must stay in sync: `rclcpp`, `diagnostic_updater`,
`geometry_msgs`, `sensor_msgs`, `tf2_ros`, `tf2_msgs`, `yaml_cpp_vendor`,
`jen_logging`, `jen_config_manager_lib_cpp`, `jen_config_manager_interface`,
`jen_parameter_msgs`, `jen_calibration_manager_msgs`.

**`fatal error: CalibrationTypes.hpp: No such file or directory`** — that
header is the alias layer over the three `Jen*` messages. If it went missing,
a partial revert removed it while `CalibrationData.hpp` still includes it.

**`error: 'kSomeParam' was not declared in this scope`** after an edit — the
constants block at the top of `src/CalibrationManagerNode.cpp` is
column-aligned by clang-format; a scripted `sed`/`str.replace` that assumed
single spaces silently no-ops. Re-read the file rather than trusting the edit.

**`git worktree` checkouts cannot be built** — no populated submodules, so it
dies at `COPY jen_logging/jen_logging ./src/jen_logging: not found`. Build
from the main clone.

**Harmless noise, the build continues past all of it:**
`Failed to set up Git hooks`, `fatal: not a git repository: /ros2_ws/src/...`,
`ERROR: no rosdep rule for 'jen_py_logging'`.

## Next

`tester` skill for the gtests and coverage, `deploy` skill to run the node,
`project` skill for how the node itself is put together.

## Migration context

Operational results, versions, counts and timings above are observations
carried from the source skill, not checks performed during migration.
Resolve sibling skills by path under this project’s `.agents/skills/`.
