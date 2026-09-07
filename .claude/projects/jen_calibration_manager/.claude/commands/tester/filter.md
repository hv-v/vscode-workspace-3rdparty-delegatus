---
description: Re-run one jen_calibration_manager gtest inside the tester image, without rebuilding
argument-hint: <gtest_filter, e.g. CalibrationManagerNodeTest.*>
allowed-tools: Bash(docker run:*), Bash(docker images:*), Read
---

Re-run a single test (or suite) from the existing
`jen_calibration_manager_build:latest` image — much faster than a rebuild, and
the only way to see a crash's own output instead of ctest's `return code -11`.

```bash
docker run --rm --entrypoint bash jen_calibration_manager_build:latest -c \
  'source /ros2_ws/install/setup.bash
   cd /ros2_ws/build/jen_calibration_manager
   ./jen_calibration_manager_test --gtest_filter=$ARGUMENTS'
```

With no argument, list what exists instead (`--gtest_list_tests`) and ask
which one to run.

Note this runs the **image's** build: source edits are not picked up until the
tester image is rebuilt (`/tester:run`). If the image does not exist yet, run
`/tester:run` first.
