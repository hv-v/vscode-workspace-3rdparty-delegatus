---
name: project
description: Orientation for the jen_calibration_manager ROS 2 node - its architecture, classes, node parameters and their YAML formats, validation checks, services, diagnostics keys, and the state of the SHIRE-1619 design_todos. Use before changing this package's code, when asked how the calibration manager works or what a parameter must contain, or when reconciling the design_todos notes with the code.
---

# jen_calibration_manager — how the package is put together

Ticket SHIRE-1619: a relay between calibration config parameters and the ROS
messages that consume them. Parameters come from `jen_config_manager`; the
node validates them, broadcasts extrinsics on `/tf` + `/tf_static`, pushes
intrinsics into camera drivers via `SetCameraInfo`, reports every check on
`/diagnostics`, and accepts single-transform updates on
`~/set_transformation`, writing them back through config_manager.

Repo root holds the ROS package in `jen_calibration_manager/`, the srv package
`jen_calibration_manager_msgs/`, the `jen_config_manager_msgs/` submodule
(where the `Jen*` message types live) and `chart/` (Helm). Ticket text and
design notes are kept outside the repo, in `.projects/jen_calibration_manager/`
(see *Workspace context* below).

## Runtime flow

```
config_manager ──set_parameters──▶ CalibrationManagerNode::onConfigurationReceived
                                        │ (on_set_parameters callback)
                                        ├─ CalibrationManager::registerCalibrationData
                                        │     └─ helpers::updateCalibrationData → CalibrationData
                                        ├─ validateCalibrationData  → Validator → visitors
                                        ├─ buildCalibrationMessages → TransformStamped lists
                                        └─ publishCalibrationData   → (gated on forwarding_enabled)
                                              ├─ CalibrationMessagePublisher → /tf, /tf_static (tf2 broadcasters)
                                              └─ CameraInfoServiceClient     → <driver>/set_camera_info
```

| file | role |
|---|---|
| `include/CalibrationTypes.hpp` | aliases the three generated `jen_parameter_msgs::msg::Jen*` types |
| `include/CalibrationData.hpp` / `src/CalibrationData.cpp` | the data holder; parsing delegates to `jen_parameter_utils::fromYaml`, plus `tfToYaml`, `mergeTransformIntoTf` |
| `CalibrationManager.*` | facade: owns the `Validator` and the current `CalibrationData` |
| `Validator.*` / `ValidationVisitor.hpp` | visitor registry; `validate` stops at the first failure, `validateAll` reports every check |
| `Publisher.*` (`CalibrationMessagePublisher`) | tf2 `TransformBroadcaster` / `StaticTransformBroadcaster` on the hardcoded `/tf`, `/tf_static` |
| `CameraInfoServiceClient.*` | per-service client cache, `SetCameraInfo` calls, failure counting |
| `CalibrationManagerNode.*` | parameters, diagnostics, `~/set_transformation`, config_manager write-back |

## Node parameters

| name | type | meaning |
|---|---|---|
| `tf` | string (YAML) | non-static transforms, updatable at runtime |
| `tf_static` | string (YAML) | fixed transforms, checksummed by config_manager |
| `camera_info` | string (YAML) | non-static intrinsics (none in current products) |
| `camera_info_static` | string (YAML) | fixed intrinsics, one entry per camera |
| `forwarding_enabled` | bool | gates all publishing/pushing (the NOT_RUNNING vs RUNNING switch; the node deliberately does not subscribe to system state) |
| `required_transformations` | string[] | `"parent:child"` entries; non-empty registers `FrameIdTopologyVisitor` |
| `diagnostics.health` | string | diagnostic task name |
| `without_config_manager` | bool | declared by `jen_config_manager_lib_cpp`; skips the blocking startup fetch |

All four calibration parameters are declared with an empty default, so a
missing one simply means "nothing in that category". Parameter *overrides*
(`--params-file`, `NodeOptions::parameter_overrides`) are applied during
declaration, before the change callback exists — the constructor therefore
re-reads them explicitly after `initializeFromConfigManager`. Keep that call
if you restructure the constructor, or file-driven runs load nothing.

### YAML shapes (what the parser actually accepts)

`tf` / `tf_static` — a map with a `transforms:` sequence mirroring
`tf2_msgs/TFMessage`:

```yaml
transforms:
  - header:
      stamp: {sec: 0, nanosec: 0}
      frame_id: base_link
    child_frame_id: camera_link
    transform:
      translation: {x: 1.0, y: 2.0, z: 3.0}
      rotation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}
```

`camera_info` / `camera_info_static` — a map with a `pairs:` sequence, each
entry pairing a target service with a `sensor_msgs/CameraInfo`:

```yaml
pairs:
  - service_name: /jen_sc_camera_driver_left/set_camera_info
    camera_info:
      header: {stamp: {sec: 0, nanosec: 0}, frame_id: "SC4:PCIE:0"}
      height: 3040
      width: 5328
      distortion_model: plumb_bob
      d: [...]
      k: [<9 values>]
      r: [<9 values>]
      p: [<12 values>]
      binning_x: 0
      binning_y: 0
      roi: {x_offset: 0, y_offset: 0, height: 0, width: 0, do_rectify: false}
```

Both are deserialized by `jen_parameter_utils::fromYaml<T>` (introspection over
the message definition), so **YAML keys are the message field names** and the
reader is **strict**: every scalar and nested-message field must be present
(`Member \`x\` not found in data.` otherwise) and fixed-size arrays (`k`, `r`,
`p`) must have their exact declared length. Variable-length arrays (`d`) may be
omitted. A document that fails to parse is logged and the whole category is
left empty — there is no per-entry skipping and no field defaulting.

## Validation and diagnostics

`CalibrationManager::initValidator()` registers, in order:
`RotationMatrixVisitor` (components in [-1,1], unit quaternion) and
`IntrinsicsValidityVisitor` (fx/fy > 0, determinant > 0, skew ≈ 0, principal
point within 25% of centre). `FrameIdTopologyVisitor` is added only when
`required_transformations` is non-empty. Every check inspects the entries that
are present, so an empty parameter set passes them all — "is anything loaded
at all" is not a validation rule.

`onHealthUpdateNeeded` emits the OK/ERROR summary from `validate()`, then one
`stat.add(<visitor name>, "ok"|reason)` per `validateAll()` result, plus
`set_camera_info_failures`. A visitor's `name()` *is* the diagnostics key —
renaming one changes the aggregation contract.

## `~/set_transformation`

`jen_calibration_manager_msgs/srv/SetTransformation` (a
`geometry_msgs/TransformStamped` in, `success` + `message` out). The handler
merges the transform into the current non-static `tf` (replacing a matching
parent/child pair, otherwise appending), serialises the *full* set with
`helpers::tfToYaml`, and calls `/config_manager/set_node_parameters`. It uses
the deferred-response pattern — the callback takes `(request_header, request)`
and `send_response` happens from the async completion lambda — because
`spin_until_future_complete` inside a live service callback would re-enter the
executor. On success it applies the new `tf` locally, which re-triggers
validate + publish.

Known soft spots: the `/config_manager/set_node_parameters` name is inferred
by analogy (`jen_config_manager_lib_cpp` only exposes the *get* constant), and
the async calls have no timeout beyond the 200ms availability wait.

## Workspace context — `.projects/jen_calibration_manager/`

Agent-neutral context, shared by Claude and Codex, at the workspace root:

| path | holds |
|---|---|
| `.task_todos/1619.md` | the SHIRE-1619 ticket: the first iteration of this node |
| `.task_todos/1590.md` | the SHIRE-1590 ticket: adopt the Shire units system in ROS messages |
| `.task_todos/1590_*.md` | 1590 working notes: unit audit, invalid fields, usage per repo, branches, changed repos, conversion-lib gaps |
| `.task_todos/readme_example.md` | a model README (from `jen_prediction_trigger`) to copy the shape of |
| `.design_todos/1619-camera-info-flow.md` | how intrinsics reach `jen_sc_camera_driver` via `SetCameraInfo`, its weak points and scenarios |
| `.design_todos/1619-jira-camera-info-flow.md`, `1757-tiket.md` | Jira drafts for the camera-info data flow |
| `.design_todos/1590-report.md`, `1590-table.md`, `1590-outofconcept.md` | the 1590 unit audit of `jen-interfaces-modules`: report, per-field table, undetermined units |
| `.examples/scene_node.md` | how `jen_scene_manager` receives a parameter from config_manager |
| `.errors/` | Docker and GitLab build logs kept for diagnosis |

Write new ticket or design notes there, never under `.claude/projects/` or
`.agents/projects/`.

## design_todos/ — read with care

> Not present in this checkout: neither the repo nor
> `.projects/jen_calibration_manager/.design_todos/` holds the files below
> (checked 2026-10-14). The warning stands for any copy that resurfaces.

`design_todos/` holds the requirements and a running commentary:

- `todo.md` — the source requirements (SHIRE-1619, 1655, 1395) and the
  tf/tf_static Q&A. Authoritative.
- `comments.todo.md` — the review that fixed the parameter names, the `Jen*`
  message shapes and the "call SetCameraInfo per camera" design.
  Authoritative; the `camera_info` example there is the format the code parses.
- `1619_followup_code.todo.md` / `1619_followup_other.todo.md` — the per-MR
  plan (9 code items, 6 non-code).
- `1619_improves_todo.md` — the improvement backlog.
- `1619_impl_summary.md`, `test_failed.todo.md`, `test_build.todo.log` —
  historical.

**The status lines in those files run ahead of the code.** They describe an
architecture pivot to `jen_parameter_utils::ConfigManagedNode` +
`declareConfigManagedParameter`, a `pairs:`-rooted `camera_info` wire format,
an `AsyncCallDeadline` helper, a `GetNodeParameters` refresh before merging,
and a camera-info retry timer. **None of that is in the code**: parsing is
hand-rolled in `CalibrationData.cpp`, and the parameter callback is
`onConfigurationReceived`. Verify against the source before trusting any
"done" claim there, and prefer `comments.todo.md` + `todo.md` when the two
disagree.

Still open from the backlog: config-manager set-service name unconfirmed, no
async timeouts, no retry for camera drivers that appear late, no product
variant (SR355 vs Specs 5) selector beyond `required_transformations`, no
coverage of the real config-manager startup path, and the non-code items
(chart example YAML, camera-driver `calib` removal, diagnostics aggregation,
docs).

## Conventions

- Docker-only builds; `clang-format -i include/*.hpp src/*.cpp test/*.cpp`
  before building (the repo-root `.clang-format` column-aligns assignments).
- New sources go into `src/Sources.cmake` / `test/Sources.cmake`.
- Logging is `LOGI/LOGW/LOGE(get_logger(), "<trace tag>", message)` from
  `jen_logging`; the trace tag is the function name.
- `build` skill to compile, `tester` skill for gtests and coverage, `deploy`
  skill to run the node for real.
