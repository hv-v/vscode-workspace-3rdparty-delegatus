---
name: deploy
description: Run the jen_calibration_manager node standalone in Docker and drive it with driver.py - probe, watch /tf and /diagnostics, nudge a republish, call set_transformation, or smoke-test it. Use when asked to run, start, launch, deploy, smoke-test or debug the live jen_calibration_manager node, or to confirm a change works in the real node rather than only in unit tests.
---

# Run and drive jen_calibration_manager

Project-specific deployment workflow; the workspace `p-deploy` is an unimplemented stub. There is no
GUI — the observable surface is DDS: the node broadcasts `/tf` + `/tf_static`,
publishes `/diagnostics`, serves `~/set_transformation`, and pushes camera
intrinsics out via `SetCameraInfo` calls.

Two files live in this skill dir and are mounted into the containers:

- `params.yaml` — a ready-made standalone config (all four calibration
  parameters, `without_config_manager: true`, a `required_transformations`
  topology list).
- `driver.py` — an rclpy driver run from a second container built on the same
  image.

Build the image first (`build` skill). Set the skill dir once — the mounts
need absolute paths, and a bare `$PWD` silently mounts a *directory* over the
file (the driver then dies with `can't find '__main__' module in
'/driver.py'`, leaving a root-owned empty dir behind):

```bash
SK=/home/vhaponov/Documents/jo-workspace/.agents/projects/jen_calibration_manager/.agents/skills/deploy
```

## Launch

```bash
docker run -d --rm --name jcm \
  --network host --ipc host -e ROS_DOMAIN_ID=42 \
  -v "$SK/params.yaml:/params.yaml:ro" \
  --entrypoint bash jen_calibration_manager \
  -c 'source /ros2_ws/install/setup.bash && exec ros2 run jen_calibration_manager jen_calibration_manager --ros-args --params-file /params.yaml'

docker logs jcm
docker rm -f jcm          # stop
```

`--network host --ipc host` are both required — see Gotchas. Healthy startup
with the shipped `params.yaml`:

```
[trace=ctor] Starting CalibrationManagerNode...
[trace=initDiagnosticUpdater] Diagnostic updater is created. Task: system/software/jen_calibration_manager
[trace=pushCameraInfo] Service '/jen_sc_camera_driver_left/set_camera_info' is not available
```

That last line is expected with no camera driver running; it is counted into
the `set_camera_info_failures` diagnostic. A
`Calibration data invalid: ...` warning instead means the parameters did not
reach the manager — check the params file actually mounted.

## Drive it

```bash
mkdir -p /tmp/jcm-out
docker run --rm --network host --ipc host -e ROS_DOMAIN_ID=42 \
  -v "$SK/driver.py:/driver.py:ro" -v /tmp/jcm-out:/out \
  --entrypoint bash jen_calibration_manager \
  -c 'source /ros2_ws/install/setup.bash && python3 /driver.py smoke'
```

| command | what it does |
|---|---|
| `probe` | nodes / topics / services actually present |
| `watch --seconds N` | capture `/tf`, `/tf_static`, `/diagnostics` |
| `nudge` | re-set the `tf` parameter to force a `/tf` republish |
| `set-transform PARENT CHILD X Y Z` | call `~/set_transformation` |
| `smoke` | all of the above, in the right order, with verdicts |

`smoke` exits non-zero if any check fails, writes `/tmp/jcm-out/report.json`,
and prints a verdict block. Verified against the current build:

```
=== VERDICT ===
  PASS  node_present
  PASS  tf_received
  PASS  tf_static_received
  PASS  diagnostics_received
  PASS  set_transformation_answered
```

The `/diagnostics` payload carries one key per validation check plus the
service-call counter — this is the fastest way to see what the node thinks of
its own data:

```json
"message": "Calibration data is valid",
"values": {"rotation_matrix": "ok", "intrinsics_validity": "ok",
           "frame_id_topology": "ok", "set_camera_info_failures": "1"}
```

### Ad-hoc poking with the ros2 CLI

Same flags, or you will see nothing:

```bash
docker run --rm --network host --ipc host -e ROS_DOMAIN_ID=42 \
  --entrypoint bash jen_calibration_manager \
  -c 'source /ros2_ws/install/setup.bash; sleep 2; ros2 node list; ros2 topic list; ros2 service list'
```

## Left/right camera_info check (with the camera driver)

`lr_camera_info_check.sh` runs two mock `jen_sc_camera_driver` instances named
as in SR355 (`jen_sc_camera_driver_left/_right`, `camera_id` `camera_left/_right`),
starts the manager with `params_lr.yaml` (different K, D, P and frame_id per
side), and runs `lr_check.py`. That script triggers a real image on each camera
and compares the `camera_info` published with it against `EXPECTED`. `-r`
also restarts both drivers without the manager to check the restore from
`~/.ros/camera_info/<camera_id>.yaml`; `-k` keeps the containers for poking.
Default images are the nexus driver `0.0.1-dev-2-MR-13-9274c24` and manager
`0.0.1-dev-38-MR-2-71445d6` — **`jen_calibration_manager:latest` has held a
msgs-only build without the node**; override with `-d` / `-m`.

Verified 2026-09-14:

- driver side PASS for both cameras: diagnostics `Calibration loaded`, image
  accepted, intrinsics and frame_id match, no cross-over between cameras;
- restore after restart PASS for intrinsics, WARN `frame_id` comes back `''`
  (`camera_calibration_parsers` does not persist `header.frame_id`);
- **manager never pushes a `--params-file` `camera_info_static` at startup**
  (phase 0 FAIL): the post-set callback fires while the parameter is still
  being declared, `has_parameter()` is false, `pairs` stay empty, so zero calls
  are made and `set_camera_info_failures` still reads `0`.
  `push_camera_info_static.py` re-sets the parameter through `set_parameters`
  as a workaround (`ros2 param load` asserts on this params file).

## Gotchas

- **`--ipc host` is mandatory for cross-container discovery.** Without it
  `ros2 node list` sometimes sees the node and rclpy reliably does not;
  `get_node_names_and_namespaces()` returns only the driver's own node and
  every wait loop times out. FastDDS's shared-memory transport lives in
  `/dev/shm`, which is per-container by default. It fails silently and
  intermittently, so it looks like a driver bug.
- **The node aborts without a config manager.** `initializeFromConfigManager`
  waits 10s for `/config_manager/get_node_parameters` then calls
  `std::abort()`. `without_config_manager: true` bypasses it — `params.yaml`
  and `chart/dev.yaml` both use that switch.
- **`/tf` is volatile and only broadcast on change.** The node publishes in
  its constructor and again from `onConfigurationReceived`. A driver that
  attaches later sees nothing — subscribe *first*, then `nudge` (it re-sets
  `tf`, which is in the watched parameter set). `smoke` already orders this
  correctly.
- **`/tf_static` is latched.** Subscribe with `TRANSIENT_LOCAL` durability or
  you miss the broadcast that already happened. `driver.py` does.
- **`set_transformation` answering `success: false` with
  `Config manager service is not available` is the correct result** when no
  config manager is running: the handler round-trips through
  `/config_manager/set_node_parameters`. What matters is that it *answers*
  within ~200ms rather than hanging.
- **Nothing is published when `forwarding_enabled` is false** — the log says
  `Data forwarding is disabled, nothing is published`. That is the
  NOT_RUNNING/RUNNING gate, not a fault.
- **`ros2 param list` prints `Node not found`** when `--ipc host` is missing.
  The driver uses the `get_parameters`/`set_parameters` services directly and
  avoids the CLI daemon entirely.
- **Driver reports `node never appeared in the ROS graph`** — almost always a
  missing `--ipc host` or a `ROS_DOMAIN_ID` mismatch between the two
  containers. Confirm the node is alive first with `docker ps` and
  `docker logs jcm`.

## Kubernetes

`chart/` (Helm) with `chart/dev.yaml` for local development. Cluster
deployment is out of scope here — this is the container-level path only.

## Migration context

Operational results, versions, counts and timings above are observations
carried from the source skill, not checks performed during migration.
Resolve sibling skills by path under this project’s `.agents/skills/`.
