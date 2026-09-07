---
description: Run the full jen_calibration_manager test stage (gtests, clang-format, gcov)
argument-hint: "[extra docker build flags]"
allowed-tools: Bash(cd:*), Bash(docker build:*), Bash(clang-format:*), Bash(grep:*), Bash(tail:*), Read
---

Run the tests for `jen_calibration_manager` via the Dockerfile `tester` stage,
per the `tester` skill.

Format first — `clang_format` is a ctest entry and fails on drift:

```bash
cd /home/vhaponov/Documents/jo-workspace/jen_calibration_manager/jen_calibration_manager
clang-format -i include/*.hpp src/*.cpp test/*.cpp
```

```bash
cd /home/vhaponov/Documents/jo-workspace/jen_calibration_manager
docker build --no-cache-filter tester --target tester -t jen_calibration_manager_build:latest . $ARGUMENTS > /tmp/build.log 2>&1
grep -E "\[  PASSED  \]|\[  FAILED  \]|tests from .* test suites ran" /tmp/build.log | tail
grep -n "error:" /tmp/build.log | head
```

`--no-cache-filter tester` is what makes the tests actually run: without it a
build with no source change replays the cached layer and emits no test output.

**A green `docker build` does not mean green tests** — `colcon test` does not
propagate failures into the exit code, so always read the grep output.
Healthy tail is `[  PASSED  ] 46 tests.` and `100% tests passed ... out of 2`.

Report the pass/fail counts, and for any failure the test name plus the
assertion or compiler error. If a test crashed (`return code -11`), isolate it
with `/tester:filter`.
