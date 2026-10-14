# 1590 — repositories changed

Branch `SH-1590-units` in each repo under `jen-shire-app-repos/`. Changes are staged, not committed.

Rule: a node may use any unit internally. Every value it writes to, or reads from, a ROS message is in the
Shire unit system, converted explicitly with `jen_unit_conversion_lib` at that write or read.

## Integration

`jen_unit_conversion_lib` is a git submodule, the same way the repos vendor `jen_logging`:

- submodule `jen_unit_conversion_lib` (falcon: `src/jen_unit_conversion_lib`) at library `master` `68626d2`
- the Dockerfile copies `jen_unit_conversion_lib/jen_unit_conversion_lib` into `src/`, colcon builds it
- the consuming package declares `<depend>jen_unit_conversion_lib</depend>` and links
  `jen_unit_conversion_lib::jen_unit_conversion_lib`

The earlier pinned Docker image stage (`FROM …/jen_unit_conversion_lib:<tag> AS unit_conversion`) is removed.
Bump the library by moving the submodule commit.

## Repositories

| Repository | Library | Write (sent in) | Read (received in) | Docker test |
|---|---|---|---|---|
| jen_lidar_falcon_driver | yes | `heater_current` A, `motor_angular_velocity` rad/s, `latency_*` s | — | not built (`libdoip` inaccessible) |
| jen_metrics_monitor | yes | — | `frequency_tolerance` % → fraction | see below |
| jen_prediction_trigger | yes | TriggerEvent `speed` m/s | ObjectTrack3D `confidence_*` % → fraction | see below |
| jen_lidar_tracker | yes | ObjectTrack3D `confidence_*` fraction → % | — | see below |
| jen_buffer_node | yes | — | GetItemByTimestamp `threshold` s → ms | see below |
| jen_camera_sim | yes (client lib) | GetItemByTimestamp `threshold` ms → s (client lib) | — | see below |
| jen_object_detection | yes (client lib) | GetItemByTimestamp `threshold` ms → s (client lib) | — | see below |
| jen_fluentbit_connector | no (Python) | `mem_used_p`, `swap_used_p` fraction → % (explicit `100.0 *`) | — | see below |
| jen_foxglove_bridge | no | interface copies only | — | not built |

Interface changes, in every vendored copy:

- `GetItemByTimestamp.srv`: `uint32 threshold_ms` → `float64 threshold  # s` (12 copies of `jen_buffer_node_interface`);
  `jen_buffer_client_lib` sends it with `convert<Second, Millisecond>` and now depends on the library
- `ObjectTrack3D.msg`: `confidence_*` documented as `[%] percent [0-100]`
- Falcon msgs: `heater_current` float64 A, `motor_angular_velocity` float64 rad/s, `latency_*` float64[6] s
- `TriggerEvent.srv` / `ValidateObject.action`: `speed` in m/s; `DiagnosticMetricConfig`: `frequency_tolerance` in %

## Checked and already correct

Hailo and Jetson metrics (°C, W, %), fluentbit CPU and thermal (%, °C), tracker `velocity` (m/s, the
algorithm's `speedKmh` is derived from it × 3.6), Falcon `uptime` (s at the source).

## Not fixed

- Falcon `temp_*` (tenths of °C) and `galvo_fpm` (frames per minute × 1000): the library has no temperature
  unit and no per-minute frame frequency; TODO at the write in `StatusConverter.cpp`.
- `ObjectDetected.confidence_*`: `ImageObjectData` documents [0-100] and the node sends it as is, but the YOLO
  code assigns raw network scores. That mismatch is inside `libalgo`, not at the message.
- Duration/Time fields: see `1590_units_todo.md`.
