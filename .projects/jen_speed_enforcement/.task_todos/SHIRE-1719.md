# SHIRE-1719: Create and set up the initial project for Speed Enforcement

| | |
|---|---|
| Type / priority | Story / Minor |
| Sprint / fix version | The Shire - Sprint 50 / MS3 |
| Epic | SHIRE-655 |
| Assignee / reporter | Valentyn Haponov / Inna Kabanova |
| Depends on | SHIRE-1695 (`jen_speed_enforcement_msgs`, Passed; MR `interfaces/jen_speed_enforcement_msgs!1` still **open**) |
| Mirror | `.atlassian/.jira/selected-for-development/SHIRE-1719.json`, pulled 2026-11-16 |

## 1. Task

Set up a new repository, **`jen_speed_enforcement`**, together with its infrastructure:

- the submodules it needs
- the sources of a basic ROS 2 node
- a SonarQube scan
- a Docker build
- Jenkins pipelines
- basic periodic health reporting to `/diagnostics`
- stubs for the unit tests. If a pipeline stage fails because coverage is too low, that stage may be commented out
  until a later commit adds enough functionality to cover.

**Acceptance criterion:** the speed enforcement node exists and contains an initial MVP implementation, moved from
`jen_evidence_rules_manager`.

**Re-estimate first.** In a ticket comment from 2026-10-19, Zach Gerstman removed the estimate. The MVP in
`jen_evidence_rules_manager` was built with a very different design to unblock other work, so this is not a plain
move. Re-estimate the ticket before starting it.

## 2. What exists today

### The MVP in `jen_evidence_rules_manager` (branch `SHIRE-1695-speed-event`)

| piece | where | what it does |
|---|---|---|
| `Enforcement` interface | `include/.../enforcements/enforcement.hpp` | `process(TriggerEvent, callback)`, `isEnabled()`, `name()` |
| `SpeedEnforcement` | `src/enforcements/speed_enforcement.cpp` (216 lines) | calls `jen_lidar_validator` directly through the `validate_object` action, compares the result with the `speed_limit` parameter and publishes `SpeedEvent` on `speed_event` |
| `speed_limit` parameter | node and `chart/values.yaml` | marked as temporary until `jen_speed_enforcement` exists |
| health diagnostics | `EvidenceRulesManager::initHealthDiagnostics` | adds a `diagnostic_updater` task named by the `diagnostics.health` parameter |
| tests | `test/test_speed_enforcement.cpp` (525 lines) | gmock against the action client |

Code-graph classes: `EvidenceRulesManager`, `Enforcement`, `EnforcementResult`, `SpeedEnforcement`,
`SpeedEnforcementTest`. Graph: `home-vhaponov-Documents-jo-workspace-jen_evidence_rules_manager`.

### The interface the new node implements: `jen_speed_enforcement_msgs` (SHIRE-1695)

- **`action/CheckSpeed.action`**
  - The goal is the `jen_vision_msgs/TriggerEvent`. The lane comes from `source_uuid`.
  - The **feedback** is sent once, straight away: an `EnforcementDecision` plus a `SpeedEvent` for the trigger speed.
    It lets the ERM request images ahead of time.
  - The **result** is the final decision. If post-validation runs, the result arrives after it, which can take
    several seconds.
- **`msg/EnforcementDecision.msg`**
  - `ERROR`: no condition covers the event, the event has no speed (`has_speed` is false), or post-validation failed
  - `CONFIRM_VIOLATION`
  - `DISCARD_EVENT`
- **`msg/SpeedEvent.msg`**
  - `speed` (`jen_units_msgs/MetersPerSecond`)
  - `base_speed_limit`, `trigger_speed_limit` (`KmH`)
  - `operational_profile_uuid` (empty for the default conditions)
  - `speed_range`
- **`msg/SpeedRange.msg`**: `IN_RANGE`, `BELOW_MINIMUM`, `ABOVE_MAXIMUM`.
- **The `post_validation` goal flag was removed** (thread at `CheckSpeed.action:11`; Inna and Jose agreed).
  Whether to post-validate is decided only by `jen_speed_enforcement`, from its own configuration.

### Design pages that bind this node

- **Rule loader and evaluator, v2 (SHIRE-1509), APPROVED.** Confluence page `286851081`; read it with
  `.atlassian/kb.sh page 286851081`.
  - A node checks each event at three levels:
    1. the limits of the active operational profile
    2. "guardrail" parameters, such as `min_confidence_*` and `default_class`
    3. `enforcement_rules`
  - If no rule matches, the node compares the speed with the profile limits and returns `CONFIRM_VIOLATION` or
    `DISCARD_EVENT`, with no post-validation.
  - The page includes an example `values.yaml` for `jen_speed_enforcement`, with the health key
    `system/software/jen_speed_enforcement`.
- **Operational Profile Design.** Confluence page `251825255`. Speed conditions come from the
  `GetSpeedConditions` service in `jen_operational_profile_msgs`.
- **Spot Speed Enforcement and VMS integration.** Confluence page `215593598`; a summary is in
  `.projects/jen_evidence_rules_manager/.design_todos/1695.md`.

### Sprint 50 tickets this one must not take over

| ticket | owner | why it matters here |
|---|---|---|
| SHIRE-1837 `jen_enforcement_rules_lib` base version | Inna Kabanova | `enforcement_rules` is evaluated there, not here |
| SHIRE-1593 / SHIRE-1591 Operational Profile Manager | Anton Brazhnyi | `GetSpeedConditions` replaces the temporary `speed_limit` |
| SHIRE-1839 Sonar ignores `sonar.properties` | Denys Dudko | the scan stage copied from ERM inherits this bug |
| SHIRE-1840 shared SonarQube task in `shire-pipeline-lib` | Denys Dudko | the Sonar stage may change shape during this sprint |

## 3. Scope

**In scope:**
- the repository, its submodules, Docker, Jenkins, Sonar and the Helm chart
- one ROS 2 node that serves `CheckSpeed`
- the MVP decision moved from the ERM: compare the speed with a configured limit, and post-validate through
  `ValidateObject`
- health diagnostics
- test stubs
- workspace onboarding

**Out of scope, each a follow-up ticket:**
- `GetSpeedConditions` and the operational profile client
- the rule engine
- VMS limits and grace periods
- uni-directional configuration
- switching the ERM from `ValidateObject` to the `CheckSpeed` client (see open question Q1)
- adding the chart to `shire-apps` (see Q5)

## 4. Target layout

The layout mirrors `jen_evidence_rules_manager`, the closest sibling, which uses the same CI library and chart base:

```
jen_speed_enforcement/                    repo root = workspace dir name = .claude/projects/ & .projects/ name
├── jen_speed_enforcement/                the ROS 2 package
│   ├── CMakeLists.txt  package.xml
│   ├── include/jen_speed_enforcement/
│   │   ├── speed_enforcement_node.hpp    rclcpp::Node + ConfigManagedNode, action server, diagnostics
│   │   ├── speed_evaluator.hpp           pure decision logic, no ROS graph → cheap to cover
│   │   └── post_validator.hpp            ValidateObject client, moved from ERM SpeedEnforcement
│   ├── src/  main.cpp  Sources.cmake  *.cpp
│   └── test/ gtest_main.cpp  Sources.cmake  *Test.cpp
├── jen_speed_enforcement_msgs/           submodule (SHIRE-1695)
├── jen_vision_msgs/  jen_buffer_node_interface/  jen_logging/
├── jen_config_manager_interface/         lib_cpp, parameter_utils, parameter_msgs, units_msgs
├── jen-static-conversion/                jen_unit_conversion_lib (km/h → m/s)
├── chart/  Chart.yaml  values.yaml  templates/deployment.yaml
├── scripts/ _common_build.sh  build.sh  build_test.sh  entrypoint.sh
├── Dockerfile  Jenkinsfile  sonar-project.properties  VERSION  .clang-format  .gitignore  README.md
```

## 5. Implementation, step by step

Each step names the skill or practice it must follow. Load the skill **before** you write the step (rule in
`.claude/rules/skills.md`). Skills that apply:

- `l-cpp`: C++, plus its `reference/multithreading.md`, `naming.md` and `formating.md`
- `l-bash`: the scripts
- `a-cpp-tester`: the only route to a test file; it is in `utests-coverage/`, so read it by path
- `a-verify-cpp`: before every commit
- the project skills `build`, `tester`, `deploy` and `project`, which step 1 creates

### Step 0: Prerequisites (operator, in the browser)

1. Re-estimate the ticket in Jira. Read the comment in §1 first.
2. Create the GitLab project `shire/jen_speed_enforcement`, the Jenkins multibranch job and the Sonar project key
   `smart-mobility-solutions_shire-jen-speed-enforcement`. The pipeline derives this key from `IMAGE_NAME`.
   Agents cannot contact `*.jenoptik.corp` (`rules/gitlab.md`), so these stay with you.
3. Check `interfaces/jen_speed_enforcement_msgs!1`.
   - Until it is merged, pin the submodule to branch `SHIRE-1695-speed-event`, as the ERM does today
     (`branch = SHIRE-1695-speed-event` in its `.gitmodules`).
   - Repin to `master` once it merges.

**Done when** the empty repo can be cloned and the Jenkins job exists.

### Step 1: Onboard the repo into the workspace

1. Add `jen_speed_enforcement` as a workspace submodule through `.gitmodules.t` and `.gitparams`, then run
   `./gen-gitmodules.sh`. **Never hand-edit `.gitmodules`** (`rules/generated-files.md`).
2. Create the project skills with the generator. Never write them by hand (`rules/skill-authoring.md`):
   ```bash
   for s in project build tester deploy; do
       ./templates/claude-templates/skills-t/new-skill.sh "$s" jen_speed_enforcement
   done
   ```
   Fill them in with verified facts only, as you learn them. Use the `jen_calibration_manager` skills as the model.
3. Add a row each to `.claude/projects/navigation_map.md` and `.projects/README.md`.
4. Mirror the change in `.agents/projects/`; `.agents/README.md` lists what to mirror.
5. Index the graph with `./docker/cbm/cbm.sh index jen_speed_enforcement`. The graph name will be
   `home-vhaponov-Documents-jo-workspace-jen_speed_enforcement`.

**Done when** the graph lists the project and `Read` of its `project` skill works by path.

### Step 2: Repo skeleton and submodules

1. Copy these from `jen_evidence_rules_manager`: `.clang-format`, `.gitignore`, `VERSION` (`0.0.1-dev`),
   `sonar-project.properties`, and `chart/templates/deployment.yaml` (`shire-common.deployment`).
2. **Do not copy:**
   - `build/`, `install/` and `log/`
   - the Qt Creator files (`*.creator*`, `*.files`, `*.includes`, `*.cflags`, `*.cxxflags`, `*.config`)
   - `local_build.sh`: it runs `colcon` on the host, which breaks the Docker-only build rule
   - the GitLab boilerplate `README.md`
3. Write a real `README.md`: what the node does, the `CheckSpeed` contract, its parameters, its diagnostics key,
   and how to build and test in Docker.
4. Submodules (`git submodule add` inside the new repo):

   | submodule | why |
   |---|---|
   | `interfaces/jen_speed_enforcement_msgs` | `CheckSpeed`, `SpeedEvent`, `EnforcementDecision` |
   | `interfaces/jen_vision_msgs` | `TriggerEvent`, `ValidateObject` |
   | `interfaces/jen_buffer_node_interface` | `jen_vision_msgs` depends on `jen_buffer_node_msgs` |
   | `jen_logging` | `LOGx` macros, `LoggingBase` |
   | `interfaces/jen_config_manager_interface` | `jen_config_manager_lib_cpp`, `jen_parameter_utils`, `jen_parameter_msgs`, `jen_units_msgs` |
   | `jen-static-conversion` | `jen_unit_conversion_lib`, for the real km/h → m/s conversion in `SpeedEvent.speed` |

   **Not needed:** `jen_scene_msgs`. `SpeedEvent` no longer carries a direction, so the ERM's `DirectionOfTravel`
   mapping does not move. Check this against the merged message before you drop it.
5. **Packages copied twice break the build.** `jen_units_msgs` arrives from up to four places. In the Dockerfile,
   copy each package exactly once and `--exclude` the nested copies, as the ERM Dockerfile does. Pin every package to
   the commit that its consumers pin. `jen_calibration_manager`'s `build` skill records the symptom (SHIRE-1796):
   `no rosdep rule for 'jen_units_msgs'`.

**Done when** `git submodule update --init --recursive` populates everything.

### Step 3: Build scripts, Dockerfile and package files (skills: `l-bash`, `l-cpp` → Build)

1. **`scripts/`:**
   - Set `ROS_PKG_NAME=jen_speed_enforcement`.
   - Apply `l-bash` while copying:
     - use `#!/usr/bin/env bash` and `set -euo pipefail` (the ERM uses only `set -e`)
     - quote `"${ROS_PKG_NAME}"`
     - print an informative message on failure
   - Keep `exec` in `entrypoint.sh`.
   - Run `shellcheck` on all four scripts.
2. **`Dockerfile`:**
   - Use the same four stages as the ERM: `builder`, `tester`, `reporter`, then the final `ros-core` image.
   - Remember that the final stage copies from `builder`, so the default build never runs tests.
3. **`CMakeLists.txt`:**
   - Build an `OBJECT` library plus the executable.
   - Set `cxx_std_20`, `-Wall -Wextra -Wpedantic` and `LOG_ID_PREFIX="${PROJECT_NAME}"`.
   - Add `--coverage` only under `BUILD_TESTING`.
   - Add `ament_clang_format`.
   - Register the gmock target from `test/Sources.cmake`.
   - Put the sources in `src/Sources.cmake`. Per `l-cpp`, a `.cpp` missing there shows up as `undefined reference`,
     not as a missing-file error.
4. **`package.xml`:** add a `<depend>` for every `find_package`. Set the maintainer to yourself; the ERM file names
   the ERM author.

**Done when** `docker build --target builder .` succeeds.

### Step 4: Pure decision logic, `SpeedEvaluator` (skill: `l-cpp`)

Build this first. It has no ROS graph, which makes it the cheapest code to cover and the one Sonar will count.

- **Input:** the speed in km/h (`TriggerEvent.speed` or the `ValidateObject` result) and the current limits (base,
  trigger, min, max).
- **Output:** a small result struct holding the `EnforcementDecision` and a filled `SpeedEvent`.
- **Rules:**
  - `has_speed == false` → `ERROR`.
  - Speed above the trigger limit → `CONFIRM_VIOLATION`; otherwise `DISCARD_EVENT`. The ERM compared with
    `speed_limit` only; in the new contract the trigger limit is the threshold. Confirm this with Q2.
  - `speed_range` is `BELOW_MINIMUM` or `ABOVE_MAXIMUM` against the min and max limits (see Q3).
  - `operational_profile_uuid` stays empty, because these are the default conditions.
- **Units** (the rule from SHIRE-1590):
  - `SpeedEvent.speed` is `MetersPerSecond` and the input is km/h, which is a real conversion. Write
    `msg.speed = jen::conversion::convertTo<unit::MetersPerSecond>(unit::KmH(speedKmh));`
  - The limits are already km/h, so write the fields directly (`msg.base_speed_limit.value = limitKmh;`).
  - Do not use `jen_units_msgs::build<…>()` or a hand-written builder.
- **`l-cpp` rules for this class:**
  - `const` by default.
  - `enum class` for internal states.
  - Return a result struct for expected outcomes. Exceptions are only for programming or startup errors.
  - camelCase for functions and locals.
  - Doxygen on the public API.

### Step 5: Post-validation client, `PostValidator` (moved from ERM `SpeedEnforcement`)

- Move `sendValidateGoal` and its mapping of `ValidateObject` statuses and result codes (`STATUS_OK`,
  `OBJECT_NOT_FOUND`, `ALREADY_REQUESTED`, `TIMEOUT`, `ABORTED`, `CANCELED`, unknown) out of
  `speed_enforcement.cpp:76-212`.
  - Every failure maps to decision `ERROR`.
  - `STATUS_OK` → `SpeedEvaluator` re-evaluates with the measured speed.
- **Improve on the MVP; do not copy it unchanged:**
  - **Hold the node by pointer, not reference.** The ERM class holds `rclcpp::Node&`, and `l-cpp` → Ownership says
    a reference member makes a class non-assignable.
  - **Stay fully async.** Use a completion callback and never wait on a future inside a callback. Per
    `l-cpp/reference/multithreading.md`, waiting on a future in a callback re-enters the executor and deadlocks.
  - **Do not add threads or a second executor.** If post-validation must not block other goals, use a callback
    group.
  - **Capture by value** whatever a lambda needs after the caller's frame is gone: the goal handle, the object id,
    the line uuid.
  - **Keep each log ID unique.** The Jenkins `Check Log IDs` stage (`generateLogIdManifest`) checks them, so rename
    `speed-enforcement-*` to IDs owned by the new package.

### Step 6: The node, `SpeedEnforcementNode` (skill: `l-cpp`)

1. It inherits from `rclcpp::Node` and `jen_parameter_utils::ConfigManagedNode<SpeedEnforcementNode>`, like
   `EvidenceRulesManager`.
2. Parameters, declared before `jen_config_manager_lib_cpp::initializeFromConfigManager(this)`:

   | name | type | note |
   |---|---|---|
   | `diagnostics.health` | string | `system/software/jen_speed_enforcement`, from the v2 design page |
   | `speed_limit` / `trigger_speed_limit` | double, km/h | **temporary** until `GetSpeedConditions` (SHIRE-1593); moved from the ERM |
   | `post_validation` | bool | **temporary** until `enforcement_rules` (SHIRE-1837); `true` keeps today's ERM behaviour (Q4) |
   | `without_config_manager` | bool | declared by the lib; needed for standalone Docker runs |

   **The calibration manager lesson:** overrides from `--params-file` are applied during declaration, before the
   change callback exists. Re-read them explicitly after `initializeFromConfigManager`, or a run that uses a params
   file loads nothing.
3. **The `check_speed` action server** (`rclcpp_action`):
   - **`handle_goal`:** accept the goal. An invalid event is answered with `ERROR` in the result, not with a
     rejection, because the contract defines `ERROR` for it.
   - **`handle_accepted`:** do not block here.
     1. Evaluate the trigger speed, then `publish_feedback` once.
     2. If `post_validation` is off, `succeed` with the same decision.
     3. If it is on, start `PostValidator` and `succeed` from its completion callback.
   - **`handle_cancel`:** accept, and abort the pending validation.
   - **No exception may escape a ROS callback** (`l-cpp` → Error handling). Catch by `const&` at the callback edge,
     log, and finish the goal with `ERROR`.
4. **`main.cpp`:** `rclcpp::init`, then `make_shared<SpeedEnforcementNode>("jen_speed_enforcement", NodeOptions{})`,
   then `spin` and `shutdown`. Keep `main.cpp` out of coverage; it is already excluded in
   `sonar-project.properties`.

### Step 7: Periodic health reporting

- Create `diagnostic_updater::Updater` with `setHardwareID("none")` and one task named by `diagnostics.health`. The
  updater publishes it periodically (1 s by default). This copies the ERM pattern.
- Report the level that is actually true, not a constant `OK`:
  - `OK`: the node is running and the `ValidateObject` server is ready.
  - `WARN`: post-validation is enabled but `ValidateObject` is not ready, so goals end in `ERROR`.
  - `ERROR`: a required parameter is missing or invalid.
- Add key/values for goals received, confirmed, discarded and errored, and for the last error.
- **These keys are an interface contract** (`l-cpp/reference/naming.md`: downstream aggregation matches on
  diagnostics keys). Once published, do not rename them casually.

### Step 8: Unit test stubs (skill: `a-cpp-tester`, the only route to a test file)

Read `.claude/skills/utests-coverage/a-cpp-tester/SKILL.md` and delegate to the `cpp-tester` agent with:

```
TEST_DIR:    <ws>/jen_speed_enforcement/jen_speed_enforcement/test
SRC_DIR:     <ws>/jen_speed_enforcement/jen_speed_enforcement/src
INCLUDE_DIR: <ws>/jen_speed_enforcement/jen_speed_enforcement/include
TARGETS:     SpeedEvaluator, PostValidator, SpeedEnforcementNode
```

What to expect from it, so you can review the result:

- **`SpeedEvaluatorTest`** covers:
  - no speed
  - below, at and above the trigger limit
  - below the minimum and above the maximum
  - the m/s conversion
- **`PostValidatorTest`** maps every `ValidateObject` status and result code. Port it from
  `test_speed_enforcement.cpp` in the ERM.
- **`SpeedEnforcementNodeTest`** covers:
  - construction with `without_config_manager`
  - the diagnostics task name
  - a `CheckSpeed` round trip against a fake `ValidateObject` server
- **Conventions:**
  - `TEST(SuiteName, TestName)` with bare identifiers, never quoted strings.
  - Every file is registered in `test/Sources.cmake`.
  - Node tests run `rclcpp::init` and `shutdown` in `SetUp`/`TearDown` and drive the executor with a **deadline
    loop**, not sleeps (`l-cpp/reference/multithreading.md`).
- If coverage still misses the Sonar gate, the ticket allows commenting out that stage in the Jenkinsfile (step 10).
  Say so in the MR and add a `TODO SHIRE-…`.

### Step 9: Build and test in Docker only (fill in the `build` and `tester` skills)

Never run `colcon` on the host. Build and test through Docker:

```bash
cd <ws>/jen_speed_enforcement
docker build --progress=plain -t jen_speed_enforcement . > /tmp/jse-build.log 2>&1
docker build --no-cache-filter tester --target tester -t jen_speed_enforcement_build:latest . > /tmp/jse-test.log 2>&1
grep -E "\[  PASSED  \]|\[  FAILED  \]|tests from .* test suites ran" /tmp/jse-test.log | tail
grep -n "error:" /tmp/jse-test.log | head
```

- **A zero exit code does not mean the tests passed.**
  - `colcon test` does not propagate failures into its exit code.
  - An all-`CACHED` log means the tests did not run.
  - Grep the log for `PASSED` and `FAILED`.
- **Check coverage per file** under `/ros2_ws/gcov` in the tester image. The aggregate includes ROS headers and is
  meaningless.
- Check `clang_format` too; it is the second ctest entry.

### Step 10: Jenkinsfile and SonarQube

1. Copy the ERM Jenkinsfile and set `IMAGE_NAME = 'shire/jen_speed_enforcement'` and
   `srcDirs: 'jen_speed_enforcement'`.
2. Keep these stages: Check Log IDs, Build & Tag (multi-arch `linux/amd64,linux/arm64`), Push, Run tests (the
   `reporter` target plus `junit`), Sonar Check, and Publish Helm Chart.
3. **Sonar:**
   - SHIRE-1839 says the scan ignores the properties file today. Pass the exclusions through `extraArgs` as well, or
     `main.cpp` counts against coverage.
   - SHIRE-1840 may replace `sonarScan` with a shared task during this sprint. Rebase onto it if it lands first.
4. If the quality gate fails only on coverage, comment out the gate check with a ticket reference, as the ticket
   allows.

**Done when** the MR pipeline is green: build, tests, push and chart.

### Step 11: Helm chart

1. **`Chart.yaml`:** `name: jen-speed-enforcement` (dashes, a Kubernetes rule), the same `shire-common` dependency
   version as the ERM, and `home` set to the new repo.
2. **`values.yaml`:** follow the v2 design page:
   - `image.name: nexus-hil.group.jenoptik.corp:8082/shire/jen_speed_enforcement`
   - `nodeName: "jen_speed_enforcement"`
   - `configManagerInit.readonly`: the `diagnostics.health` key and the temporary limits, each with a `schemas:`
     entry (`writable: false` and a type)
   - Leave out `enforcement_rules` and `min_confidence_*`; they arrive with SHIRE-1837.
3. Render it offline with the `shire-apps` `deploy` skill (a scratch umbrella with the local chart). Do not claim
   anything about restarts or persistence beyond what the shipped charts mount.

### Step 12: Smoke test the running node (fill in the `deploy` skill)

1. Run the image with `--network host --ipc host -e ROS_DOMAIN_ID=<n>` and a params file that sets
   `without_config_manager: true`.
2. From a second container, send a `CheckSpeed` goal (`ros2 action send_goal --feedback`) with a `TriggerEvent`
   above the limit and another below it.
3. Expect:
   - the feedback first, then the result
   - `ERROR` when `has_speed` is false
   - `ERROR` plus a `WARN` diagnostic when `ValidateObject` is absent and post-validation is on
   - `/diagnostics` carrying `system/software/jen_speed_enforcement`
4. Keep a `driver.py` and `params.yaml` in the `deploy` skill directory, as `jen_calibration_manager` does.

### Step 13: Verify, commit and open the MR

1. Run `a-verify-cpp` on the repo, which delegates to `cpp-verifier`. Fix what it reports, then rebuild in Docker.
2. Commit only when you ask for it. Use one MR on the new repo, titled `SHIRE-1719: …`.
3. Then run `.gitlab/sync.sh add <MR link>`, followed by `pull`, to follow its pipeline and threads.

## 6. Open questions (ask before the step that needs them)

| # | question | blocks |
|---|---|---|
| Q1 | Does "moved from the evidence rules manager" include switching the ERM's `SpeedEnforcement` to a `CheckSpeed` client and removing its `speed_limit` and `ValidateObject` code in this ticket, or is that a separate ERM ticket? | scope, ERM MR |
| Q2 | For the MVP, is the violation threshold `trigger_speed_limit` or `base_speed_limit`? The ERM used one `speed_limit` for both. | step 4 |
| Q3 | Where do the min and max for `SpeedRange` come from? The Confluence example is "< 10 km/h" / "> 300 km/h". Should they be parameters, or stay `IN_RANGE` until operational profiles? | step 4 |
| Q4 | Should there be a temporary `post_validation` parameter until SHIRE-1837, or should every event always be post-validated as the ERM does now? | steps 5–6 |
| Q5 | Should the chart be added to `shire-apps/shire-base/Chart.yaml` in this ticket or later? | step 11 |
| Q6 | Is the GitLab group `shire/` (not `shire/spikes/`) and the Sonar key from §5 step 0 right? | step 0 |

## 7. Definition of done

- [ ] The repo is created and onboarded: workspace submodule, project skills, navigation maps, code graph.
- [ ] `docker build` and the `tester` target pass. The log shows `[  PASSED  ]`, `clang_format` is clean, and
      per-file coverage has been reviewed.
- [ ] The node serves `check_speed`, sends feedback and then a result, and post-validates through `validate_object`.
- [ ] `/diagnostics` reports `system/software/jen_speed_enforcement` with a real level.
- [ ] The Jenkins pipeline is green, and any Sonar stage that is commented out has a ticket reference.
- [ ] The chart publishes and renders offline.
- [ ] `a-verify-cpp` returns no open findings.
- [ ] The `build`, `tester`, `deploy` and `project` skills are filled in with verified facts.
