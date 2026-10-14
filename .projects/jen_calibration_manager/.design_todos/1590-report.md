# SHIRE-1590 — unit-system audit of `jen-interfaces-modules`

Audit of every ROS interface definition in
`/home/vhaponov/Documents/jo-workspace/jen-interfaces-modules` against the unit
system specified in `.task_todos/1590.md` ("Units of measurement for the Shire
and ROS messages").

- **Scope:** 90 `.msg` / `.srv` / `.action` files across 12 repositories.
- **Method:** the folder was indexed as the CBM graph
  `home-vhaponov-Documents-jo-workspace-jen-interfaces-modules`
  (4446 nodes, 9323 edges). The graph indexes only C++/Python/Bash/YAML — it
  holds **no** ROS IDL nodes — so the file-level analysis is scoped text search,
  which is the documented fallback for what the graph cannot hold.
- `jen_config_manager_interface/jen_scene_msgs/` is byte-identical to the
  top-level `jen_scene_msgs/` (same vendored submodule) and is counted once.
- `jen_calibration_manager_msgs/` contains only an empty `README.md` — no
  interface files, nothing to audit.

---

## 0. Headline finding — the unit-message layer does not exist

The spec's *ROS implementation* section requires every unit of measurement to be
carried by a dedicated message type (`Meters.msg`, `Celsius.msg`, `Percent.msg`,
`KmH.msg`, …), all with `float64` as the data type, so that "no more comments
needed within the .msg file" describe the unit.

**Not one such message exists anywhere in `jen-interfaces-modules`.** Every unit
in the tree is currently expressed as a bare primitive plus, at best, a name
suffix or a comment. This means *all* of the findings below are ultimately the
same defect; the sections separate them by how bad the current state is.

There is also no package that would host these shared types. A prerequisite
decision for SHIRE-1590 is **where** `Meters.msg` and friends live — a new
`jen_units_msgs` repository is the obvious candidate, since every package listed
below would depend on it.

---

## 1. Incorrect unit system — a non-SI or arbitrary unit is used

These state a unit, and the unit is wrong under the spec.

### 1.1 Speed reported in km/h — explicitly contradicts the spec

The spec's *Measurements of speed* section: "All measurements of speed are
communicated as meters per second as far into the chain as possible."

| file | line | field | problem |
|---|---|---|---|
| `jen_vision_msgs/srv/TriggerEvent.srv` | 32-35 | `float64 speed` | comment says "in km/h" |
| `jen_vision_msgs/action/ValidateObject.action` | 23-25 | `float64 speed` | comment says "in km/h" |

These are the clearest violations in the tree: the unit is documented, and it is
documented as the wrong one. Both are on the trigger/validation path, i.e. deep
in the chain, which is exactly where the spec demands m/s.

> Note: the spec does list `KmH.msg` as an example of a derived-unit message, so
> km/h is a legal *type* at the customer-facing edge — but not here.

### 1.2 Arbitrary units — forbidden outright

The spec's *Communication* section: "Unitless messages are not allowed, as well
as no messages with arbitrary units."

| file | line | field | unit used | should be |
|---|---|---|---|---|
| `jen_lidar_falcon_driver_msgs/msg/FalconStatusCounters.msg` | 16-18 | `latency_10us_average`, `latency_10us_variation`, `latency_10us_max` | ticks of 10 µs | `builtin_interfaces/Duration` |
| `jen_lidar_falcon_driver_msgs/msg/FalconStatusCounters.msg` | 27-28 | `netstat_rx_speed_kbps`, `netstat_tx_speed_kbps` | kbit/s | SI-derived bit rate |
| `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | 9 | `motor_rpm` | revolutions/minute | Hz or rad·s⁻¹ |
| `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | 12 | `galvo_fpm` | frames/minute | Hz |
| `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | 17-18 | `moisture_index`, `window_blockage_index` | unnamed "index" | undefined scale — needs a definition or `Percent` |
| `jen_system_msgs/msg/FluentbitMemoryMetrics.msg` | 3-5, 8-10 | `mem_free`, `mem_total`, `mem_used`, `swap_*` | `[Kilobytes]` | kilobyte is not an SI unit; bytes are not in the Shire unit system at all |
| `jen_accelerator_metrics_msgs/msg/JetsonDeviceStatus.msg` | 5 | `mem_used_bytes` | bytes | same |
| `jen_detector_msgs/…/LicensePlate.msg` | 7 | `characters_height_px` | pixels | pixels are not in the unit system |
| `jen_detector_msgs/…/PlateReaderModelInfo.msg` | 5-7 | `optimal_character_height`, `model_input_height`, `model_input_width` | pixels | same |
| `jen_vision_msgs/msg/PlateRecognition.msg` | 17 | `character_height` | pixels (per comment) | same |

**Bytes and pixels need a spec decision, not a code change.** They are real,
unavoidable quantities that the Shire unit system as written does not cover.
Either the spec grows a documented exception (as it already did for °C), or
these fields cannot be made compliant. This is the single largest open question
in the audit and should go back to Dennis Grannemann / Benedikt Bergenthal.

### 1.3 Non-SI time units, where the spec mandates the ROS time types

The spec's *Time units* section: "Time measurements are stored in ROS msg/Time
Message."

| file | line | field | problem |
|---|---|---|---|
| `jen_hal_msgs/msg/ClocksStatus.msg` | 3 | `int64 clock_diff_ms` | milliseconds in an integer; should be `builtin_interfaces/Duration` |
| `jen_buffer_node_interface/jen_buffer_node_msgs/srv/GetItemByTimestamp.srv` | 2 | `uint32 threshold_ms` | milliseconds; should be `Duration`. Also carries no comment |
| `jen_lidar_falcon_driver_msgs/msg/FalconStatusExtended.msg` | 3 | `float64 timestamp` | a raw float epoch; should be `builtin_interfaces/Time` |
| `jen_lidar_falcon_driver_msgs/msg/FalconStatus.msg` | 10 | `float64 uptime` | comment "Falcon uptime" states no unit; should be `Duration` |
| `jen_lidar_falcon_driver_msgs/msg/FalconStatusCounters.msg` | 10-11 | `power_up_time_in_second`, `process_up_time_in_second` | second is the right SI unit, but as `uint32`, not `Duration` |
| `jen_lidar_falcon_driver_msgs/msg/FalconStatusCounters.msg` | 34 | `lifelong_uptime` | no unit at all, in any form |

### 1.4 Non-SI prefix on an SI base unit

| file | line | field | problem |
|---|---|---|---|
| `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | 20 | `uint16 heater_current_ma` | milliamperes; base unit is **A** |

---

## 2. Unit not defined — no comment, no unit message, not even a name suffix

These are the "unit system is not defined by comment" cases. A reader cannot
tell what the number means.

| file | line | field | what is undefined |
|---|---|---|---|
| `jen_hal_msgs/msg/PowerSupplyStatus.msg` | 1-2 | `voltage`, `current` | volts? millivolts? amperes? The file has no comments at all |
| `jen_camera_msgs/msg/ImageMetadata.msg` | 14-15 | `latitude`, `longitude` | degrees or radians — the comment describes the semantics ("Camera position. 0/0 = not available.") but never the unit |
| `jen_vision_msgs/msg/ObjectTrack3D.msg` | 7 | `geometry_msgs/Vector3 velocity` | no unit stated anywhere in the file; given §1.1, m/s vs km/h is a live ambiguity here |
| `jen_vision_msgs/msg/ObjectTrack3D.msg` | 9-11 | `confidence_speed`, `confidence_pose`, `confidence_dimension` | no range, no unit |
| `jen_vision_msgs/msg/PlateRecognition.msg` | 10-11 | `vrn_confidence`, `country_confidence` (`uint8`) | comment is only "# Confidence scores" — no range, no unit |
| `jen_sr355_alignment_msgs/msg/LidarAlignmentParameterValue.msg` | 2 | `float32 value` | a wholly generic value with no unit — the archetypal "arbitrary units" case |
| `jen_sr355_alignment_msgs/msg/LidarAlignmentBFotoLine.msg` | 1 | `float32 distance` | metres? pixels? No comment in the file |
| `jen_sr355_alignment_msgs/msg/LidarAlignmentTriggerLine.msg` | 4-5 | `float32 distance`, `int32 direction` | distance unit undefined; `direction` is a bare int with no enum |
| `jen_sr355_alignment_msgs/msg/CameraImageParameters.msg` | 3 | `float64 gain` | dimensionless? dB? |
| `jen_sr355_alignment_msgs/msg/LidarAlignmentImageRequest.msg` | 2 | `float64 gain` | same |
| `jen_camera_msgs/msg/CameraParameters.msg` | 2 | `float64 gain_factor` | same |
| `jen_detector_msgs/…/Point2D.msg` | 1-2 | `x`, `y` | pixels or metres — no comment at all |
| `jen_buffer_node_interface/jen_buffer_node_msgs/msg/BufferItemResponse.msg` | 6-7 | `item_offset`, `item_size` | bytes assumed, never stated |
| `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | 3-8 | `temp_fpga`, `temp_laser`, `temp_adc`, `temp_board`, `temp_det[4]`, `temp_other[3]` | `int16` temperatures with no unit and no scale factor |
| `jen_lidar_falcon_driver_msgs/msg/FalconStatus.msg` | 5-9 | `temp_fpga`, `temp_adc`, `temp_board`, `temp_laser`, `temp_det[4]` | same |
| `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | 16 | `galvo_offset_angle_client` | an angle with no unit — rad and deg are both legal in the spec, so this is genuinely ambiguous |
| `jen_sr355_alignment_msgs/msg/LidarAlignmentImage.msg` | 3 | `int32 binning` | dimensionless factor, undocumented |

### 2.1 Geometry with an implied-only unit

`jen_scene_msgs/msg/Lane.msg` (`left_boundary`, `right_boundary`),
`TriggerLine.msg` (`start`, `end`) and `TriggerZone.msg` (`polygon`) use
`geometry_msgs/Point`. The comments carefully define the *frame* and the pixel
convention, but never the unit for the world case. REP-103 implies metres; the
spec requires it to be stated. **Low severity** — the intent is documented, only
the unit is left to convention.

---

## 3. Correct unit, wrong encoding

The unit here is right under the spec, but it lives in a field-name suffix or a
comment rather than in a type, and often has the wrong primitive.

| file | line | field | note |
|---|---|---|---|
| `jen_hal_msgs/msg/Temperature.msg` | 1 | `float64 temperature_c` | °C correct; should be `Celsius.msg`. No comment |
| `jen_accelerator_metrics_msgs/msg/HailoDeviceStatus.msg` | 3-5 | `temperature_c`, `utilization_pct`, `power_w` | °C, %, W all correct; all should be unit types. File has no comments |
| `jen_accelerator_metrics_msgs/msg/JetsonDeviceStatus.msg` | 2-4, 6 | `temperature_c`, `utilization_pct`, `power_w`, `mem_used_pct` | same |
| `jen_accelerator_metrics_msgs/msg/HailoWorkloadStatus.msg` | 2 | `utilization_pct` | same |
| `jen_system_msgs/msg/FluentbitThermalZone.msg` | 5 | `float32 temp # [°C]` | unit documented and correct; `float32` not `float64`, no `Celsius.msg`. **This is the file the spec itself uses as the worked example** |
| `jen_system_msgs/msg/FluentbitCPUMetrics.msg` | 3-5 | `cpu_p`, `system_p`, `user_p` | documented as `[0.0 - 100.0]`; should be `Percent.msg`. Also the spec's worked example |
| `jen_system_msgs/msg/FluentbitCPUCoreMetrics.msg` | 3-5 | `p_cpu`, `p_system`, `p_user` | same |
| `jen_system_msgs/msg/FluentbitMemoryMetrics.msg` | 6, 11 | `mem_used_p`, `swap_used_p` | percent, `float32`; should be `Percent.msg` |
| `jen_lidar_falcon_driver_msgs/msg/FalconStatusCounters.msg` | 23-24, 33 | `cpu_percentage`, `mem_percentage`, `sys_cpu_percentage` | percent as `uint16`; should be `Percent.msg` |
| `jen_detector_msgs/…/LicensePlate.msg` | 3-5 | `confidence_read`, `confidence_country`, `confidence_detection` | range `(0-100)` documented; is a percentage, should be `Percent.msg` |
| `jen_detector_msgs/…/LicensePlate.msg` | 8 | `characters_rotation_deg` | deg is a legal derived unit; should be a `Degrees` type |
| `jen_vision_msgs/msg/PlateRecognition.msg` | 20 | `float32 plate_angle_deg` | same |

---

## 4. Clean — no unit-bearing fields

No findings in these files; they carry only identifiers, enums, strings or
already-correct ROS time types.

`jen_camera_msgs/`: `CameraImageGoal.msg` (uses `Time`/`Duration` correctly),
`CameraImageResult.msg`, `FlashRequest.msg`, `CameraImage.action` ·
`jen_scene_msgs/`: `DirectionOfTravel.msg`, `TriggerPosition.msg`, `Scene.msg`,
`SetSceneParameter.srv` · `jen_vision_msgs/`: `ObjectClassMapping.msg`,
`ObjectClassMappingArray.msg`, `ObjectDirection.msg`, `ObjectGeometryType.msg`,
`ObjectLost.msg`, `ObjectTrack3DArray.msg`, `Pose2DStamped.msg`,
`TriggerEventType.msg`, `ClearObjectData.srv` · all of
`jen_config_manager_interface/jen_config_manager_interface/` ·
`jen_buffer_node_msgs/ItemHeader.msg` and the remaining `srv/` ·
`jen_detector_msgs/`: `ObjectDetected.msg`, `Vehicle.msg`,
`VehicleDetectorModelInfo.msg` · `jen_lidar_falcon_driver_msgs/`: all enum and
fault messages, `LidarInfo.msg`, both `srv/` · `jen_sr355_alignment_msgs/`:
`LidarAlignmentMarkerpoint(s).msg`, `LidarAlignmentPolygon2d.msg`,
`LidarAlignmentOverlay.msg`, `LidarAlignmentLaneMarkers.msg`,
`LidarAlignmentParameter(Entry).msg`, `LidarAlignmentTriggerLines.msg`,
`LidarAlignmentWriteRequest.msg` · `jen_system_msgs/FluentbitThermalMetrics.msg`

---

## 5. Suggested order of work

1. **Resolve the spec gaps first** — bytes, pixels and dimensionless
   confidence scores have no home in the unit system as written (§1.2). Nothing
   downstream can be made compliant until that is decided.
2. **Create the unit-message package** (§0) — `Meters`, `Celsius`, `Percent`,
   `MetersPerSecond`, `Watts`, `Volts`, `Amperes`, `Degrees`, `Hertz`.
3. **Fix the two km/h speed fields** (§1.1) — the only findings that are
   actively documented as wrong, and named directly by the spec.
4. **Fix the time fields** (§1.3) — mechanical, and `builtin_interfaces` already
   provides the types, so no dependency on step 2.
5. **Fill in §2** — undefined units. Each needs someone who knows the producing
   node; several are genuinely ambiguous (`velocity`, `galvo_offset_angle_client`,
   the `LidarAlignment*` distances) and must not be guessed.
6. **Migrate §3** — the largest volume but the lowest risk, since the intended
   unit is already known and correct.

`jen_lidar_falcon_driver_msgs` is worth calling out: it accounts for roughly a
third of all findings and mirrors a vendor SDK's field layout. Changing it may
mean adding a translation layer in the driver rather than editing the interface,
which is a design decision rather than a mechanical fix.

---

## Not covered by this audit

The 1590 acceptance criteria also require that tests pass and that the system is
deployed and smoke-tested after the changes. This report covers only the first
criterion — identifying which messages need to change. No code was modified.
