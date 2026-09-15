---
name: tester
description: Run and debug the jen_calibration_manager gtests, clang-format lint and gcov coverage via the Dockerfile tester stage. Use when asked to test jen_calibration_manager, run or filter a single test, check its coverage, or diagnose a failing, crashing or newly added test in this repo.
---

# Test jen_calibration_manager

Project-specific test workflow; the workspace `p-tester` is an unimplemented stub. Verified
against this repo at 23 gtests in 7 suites, all passing, `clang_format`
clean.

`scripts/build_test.sh` builds the dependencies with `-DBUILD_TESTING=OFF`
first and only this package with `-DBUILD_TESTING=ON`. Turning testing on for
everything `--packages-up-to` pulls in also compiles *their* test targets -
`jen_parameter_utils`'s tests currently do not compile (see Traps).

```bash
WS=/home/vhaponov/Documents/jo-workspace
cd "$WS/jen_calibration_manager"
```

## Run everything

```bash
docker build --no-cache-filter tester --target tester -t jen_calibration_manager_build:latest . > /tmp/build.log 2>&1
grep -E "\[  PASSED  \]|\[  FAILED  \]|tests from .* test suites ran" /tmp/build.log | tail
grep -n "error:" /tmp/build.log | head        # compile errors in test sources
```

`--no-cache-filter tester` forces `RUN ./build_test.sh` to re-execute while the
`builder` stage stays cached (~24s). Without it, a build with no source change
replays the cached layer and prints **no test output at all** - every line says
`CACHED` and the greps above match nothing, which looks exactly like "no
failures". An all-`CACHED` log is not evidence of a green run.

**The image builds even when tests fail** — `colcon test` does not propagate
failures into its exit code. Always grep; never trust `EXIT=0` alone.

Healthy tail: `[  PASSED  ] 23 tests.` and `100% tests passed, 0 tests failed
out of 2` (the two ctest entries are the gtest binary and `clang_format`).

## Re-run one test without rebuilding

The tester image keeps the build tree, so iterate there — far faster than a
rebuild, and the only way to see a crash:

```bash
docker run --rm --entrypoint bash jen_calibration_manager_build:latest -c \
  'source /ros2_ws/install/setup.bash
   cd /ros2_ws/build/jen_calibration_manager
   ./jen_calibration_manager_test --gtest_filter=CalibrationManagerNodeTest.*'
```

`--gtest_list_tests` enumerates them. Note this runs the *image's* build, so
source edits need a rebuild before they show up.

## What the suites cover

| file | suites | notes |
|---|---|---|
| `test/CalibrationDataTest.cpp` | `CalibrationDataTest` | YAML parsing of all four parameters, `tfToYaml` round trip, merge helper |
| `test/CalibrationManagerTest.cpp` | `CalibrationManagerTest` | validate / validateAll, partial parameter updates, transform merge |
| `test/ValidationVisitorTest.cpp` | one suite per visitor | rotation, intrinsics, frame-id topology |
| `test/ValidatorTest.cpp` | `ValidatorTest` | visitor registration, first-failure vs. validateAll |
| `test/PublisherTest.cpp` | `CalibrationMessagePublisherTest` | real DDS round trip on `/tf` and `/tf_static` |
| `test/CameraInfoServiceClientTest.cpp` | `CameraInfoServiceClientTest` | SetCameraInfo push, failure counting |
| `test/CalibrationManagerNodeTest.cpp` | `CalibrationManagerNodeTest` | node construction, diagnostics keys, forwarding gate, `~/set_transformation` |

Node and publisher tests spin a real `rclcpp` graph: they `rclcpp::init` in
`SetUp` and `rclcpp::shutdown` in `TearDown`, and drive an executor with
deadline loops. Keep that pattern for new ones — a test that never spins will
hang or silently observe nothing.

## Coverage

`scripts/build_test.sh` runs `gcov` after `colcon test`; output lands in
`/ros2_ws/gcov/` inside the tester image. The aggregate over every `.gcov`
includes all ROS headers and reads ~18% — meaningless. Use the per-file view:

```bash
docker run --rm --entrypoint python3 jen_calibration_manager_build:latest -c "
import glob
for f in sorted(glob.glob('/ros2_ws/gcov/*.gcov')):
    name = f.split('/')[-1]
    if name.endswith('Test.cpp.gcov'): continue
    if not any(k in name for k in ['Calibration','Validat','Publisher','CameraInfo']): continue
    counts = [l.split(':',1)[0].strip() for l in open(f, errors='ignore')]
    hit = sum(1 for c in counts if c.isdigit()); tot = hit + sum(1 for c in counts if c=='#####')
    if tot: print(f'{name}: {hit}/{tot} ({100*hit/tot:.0f}%)')
"
```

Last measured: `CalibrationData.cpp` 98%, `CalibrationManager.cpp` 100%,
`CalibrationManagerNode.cpp` 88%, `CameraInfoServiceClient.cpp` 100%,
`Publisher.cpp` 93%, `Validator.cpp` 100%. `ValidationVisitor.hpp` reports low
because header instantiations are counted once per object file — ignore it.

## Traps

- **`run_test.py: return code -11` is SIGSEGV**, not an assertion failure.
  ctest reports the whole binary as one failed test and every result after
  the crash is lost. Isolate with `--gtest_filter`.
- **A `TEST()` macro's test name must be a bare identifier**, not a quoted
  string: `TEST(CalibrationDataTest, ParsesTfTransforms)`.
- **`ament_clang_format` reads `${CMAKE_SOURCE_DIR}/../.clang-format`** — the
  config at the *repo* root, not inside the package. Run
  `clang-format -i include/*.hpp src/*.cpp test/*.cpp` before building; the
  host binary and the CI one agree on this config.
- **`clang_format` is its own ctest entry.** `1 - clang_format (Failed)`
  alongside `[  PASSED  ] N tests.` means formatting drift, not broken code.
- **Do not widen `-DBUILD_TESTING=ON` back to `--packages-up-to`.**
  `jen_parameter_utils` generates `types.hpp` with a naive PascalCase-to-snake
  conversion that emits `jen_parameter_msgs/msg/jen_t_f_message.hpp` for
  `JenTFMessage.msg`, while rosidl generates `jen_tf_message.hpp`. Its own
  tests then fail to compile and take the whole tester stage down with them.
  The library itself is fine - only `types.hpp` (and `config_managed_node.hpp`,
  which includes it) is affected. The real fix belongs in the
  `jen_config_manager_msgs` repo.
- **Tests that wait on an absent service cost real time** — the camera-info
  client waits 200ms per unavailable service and `~/set_transformation` waits
  200ms for config_manager. Both are deliberate; do not "fix" them by
  shortening the deadline loops.
- **Node tests drive parameters directly** with `parameter_overrides` and
  `onConfigurationReceived`; the real config-manager startup path
  (`initializeFromConfigManager` doing a live service call) has no coverage
  here. Use the `deploy` skill for that half.

## Migration context

Operational results, versions, counts and timings above are observations
carried from the source skill, not checks performed during migration.
Resolve sibling skills by path under this project’s `.agents/skills/`.
