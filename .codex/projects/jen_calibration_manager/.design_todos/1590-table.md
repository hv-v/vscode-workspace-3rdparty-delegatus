# SHIRE-1590 — unit conversion table

Row-per-property companion to [1590-report.md](1590-report.md). Every field in
`jen-interfaces-modules` that needs a unit change under the Shire unit system
gets its own row, even when several fields sit in the same message.

- **Paths** are relative to `/home/vhaponov/Documents/jo-workspace/jen-interfaces-modules/`.
- **Target Unit** names the proposed unit message from the spec's *ROS
  implementation* section. **None of these types exist yet** — creating them is
  prerequisite work, see §0 of the report.
- **Conversion Formula** — `1:1` means the value is already numerically correct
  and only the type changes. `⚠ unknown` means the current unit is genuinely
  undetermined and must be confirmed with the producing node before any formula
  can be written. Do not guess these.
- **`spec gap`** marks bytes and pixels, which the Shire unit system does not
  currently cover at all. These need a spec decision, not a conversion.

96 rows.

| Name | Path | Variable Name | Current Unit | Target Unit | Conversion Formula |
|---|---|---|---|---|---|
| HailoDeviceStatus | `jen_accelerator_metrics_msgs/msg/HailoDeviceStatus.msg` | `temperature_c` | °C (in name only) | `Celsius.msg` (°C) | 1:1 |
| HailoDeviceStatus | `jen_accelerator_metrics_msgs/msg/HailoDeviceStatus.msg` | `utilization_pct` | % (in name only) | `Percent.msg` (%) | 1:1 |
| HailoDeviceStatus | `jen_accelerator_metrics_msgs/msg/HailoDeviceStatus.msg` | `power_w` | W (in name only) | `Watts.msg` (W) | 1:1 |
| HailoWorkloadStatus | `jen_accelerator_metrics_msgs/msg/HailoWorkloadStatus.msg` | `utilization_pct` | % (in name only) | `Percent.msg` (%) | 1:1 |
| JetsonDeviceStatus | `jen_accelerator_metrics_msgs/msg/JetsonDeviceStatus.msg` | `temperature_c` | °C (in name only) | `Celsius.msg` (°C) | 1:1 |
| JetsonDeviceStatus | `jen_accelerator_metrics_msgs/msg/JetsonDeviceStatus.msg` | `utilization_pct` | % (in name only) | `Percent.msg` (%) | 1:1 |
| JetsonDeviceStatus | `jen_accelerator_metrics_msgs/msg/JetsonDeviceStatus.msg` | `power_w` | W (in name only) | `Watts.msg` (W) | 1:1 |
| JetsonDeviceStatus | `jen_accelerator_metrics_msgs/msg/JetsonDeviceStatus.msg` | `mem_used_bytes` | bytes | **spec gap** — not in unit system | ⚠ needs spec decision |
| JetsonDeviceStatus | `jen_accelerator_metrics_msgs/msg/JetsonDeviceStatus.msg` | `mem_used_pct` | % (in name only) | `Percent.msg` (%) | 1:1 |
| BufferItemResponse | `jen_buffer_node_interface/jen_buffer_node_msgs/msg/BufferItemResponse.msg` | `item_offset` | — (undefined, bytes assumed) | **spec gap** — not in unit system | ⚠ needs spec decision |
| BufferItemResponse | `jen_buffer_node_interface/jen_buffer_node_msgs/msg/BufferItemResponse.msg` | `item_size` | — (undefined, bytes assumed) | **spec gap** — not in unit system | ⚠ needs spec decision |
| GetItemByTimestamp | `jen_buffer_node_interface/jen_buffer_node_msgs/srv/GetItemByTimestamp.srv` | `threshold_ms` | ms (`uint32`) | `builtin_interfaces/Duration` | `sec = ms / 1000`; `nanosec = (ms % 1000) * 1e6` |
| CameraParameters | `jen_camera_msgs/msg/CameraParameters.msg` | `gain_factor` | — (undefined) | dimensionless (document it) | 1:1 if already a plain factor — ⚠ confirm not dB |
| ImageMetadata | `jen_camera_msgs/msg/ImageMetadata.msg` | `latitude` | — (undefined) | `Degrees.msg` (deg) | ⚠ unknown — deg vs rad unconfirmed |
| ImageMetadata | `jen_camera_msgs/msg/ImageMetadata.msg` | `longitude` | — (undefined) | `Degrees.msg` (deg) | ⚠ unknown — deg vs rad unconfirmed |
| LicensePlate | `jen_detector_msgs/jen_detector_msgs/msg/LicensePlate.msg` | `confidence_read` | 0–100 (per comment) | `Percent.msg` (%) | 1:1 |
| LicensePlate | `jen_detector_msgs/jen_detector_msgs/msg/LicensePlate.msg` | `confidence_country` | 0–100 (per comment) | `Percent.msg` (%) | 1:1 |
| LicensePlate | `jen_detector_msgs/jen_detector_msgs/msg/LicensePlate.msg` | `confidence_detection` | 0–100 (per comment) | `Percent.msg` (%) | 1:1 |
| LicensePlate | `jen_detector_msgs/jen_detector_msgs/msg/LicensePlate.msg` | `characters_height_px` | pixels | **spec gap** — not in unit system | ⚠ needs spec decision |
| LicensePlate | `jen_detector_msgs/jen_detector_msgs/msg/LicensePlate.msg` | `characters_rotation_deg` | deg | `Degrees.msg` (deg) | 1:1 |
| PlateReaderModelInfo | `jen_detector_msgs/jen_detector_msgs/msg/PlateReaderModelInfo.msg` | `optimal_character_height` | pixels | **spec gap** — not in unit system | ⚠ needs spec decision |
| PlateReaderModelInfo | `jen_detector_msgs/jen_detector_msgs/msg/PlateReaderModelInfo.msg` | `model_input_height` | pixels | **spec gap** — not in unit system | ⚠ needs spec decision |
| PlateReaderModelInfo | `jen_detector_msgs/jen_detector_msgs/msg/PlateReaderModelInfo.msg` | `model_input_width` | pixels | **spec gap** — not in unit system | ⚠ needs spec decision |
| Point2D | `jen_detector_msgs/jen_detector_msgs/msg/Point2D.msg` | `x` | — (undefined) | `Meters.msg` (m) or pixels | ⚠ unknown — px vs m unconfirmed |
| Point2D | `jen_detector_msgs/jen_detector_msgs/msg/Point2D.msg` | `y` | — (undefined) | `Meters.msg` (m) or pixels | ⚠ unknown — px vs m unconfirmed |
| ClocksStatus | `jen_hal_msgs/msg/ClocksStatus.msg` | `clock_diff_ms` | ms (`int64`) | `builtin_interfaces/Duration` | `sec = ms / 1000`; `nanosec = (ms % 1000) * 1e6` |
| PowerSupplyStatus | `jen_hal_msgs/msg/PowerSupplyStatus.msg` | `voltage` | — (undefined) | `Volts.msg` (V) | 1:1 if already V — ⚠ confirm not mV |
| PowerSupplyStatus | `jen_hal_msgs/msg/PowerSupplyStatus.msg` | `current` | — (undefined) | `Amperes.msg` (A) | 1:1 if already A — ⚠ confirm not mA |
| Temperature | `jen_hal_msgs/msg/Temperature.msg` | `temperature_c` | °C (in name only) | `Celsius.msg` (°C) | 1:1 |
| FalconSensorReadings | `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | `temp_fpga` | — (undefined, `int16`) | `Celsius.msg` (°C) | ⚠ unknown — vendor scale factor unconfirmed |
| FalconSensorReadings | `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | `temp_laser` | — (undefined, `int16`) | `Celsius.msg` (°C) | ⚠ unknown — vendor scale factor unconfirmed |
| FalconSensorReadings | `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | `temp_adc` | — (undefined, `int16`) | `Celsius.msg` (°C) | ⚠ unknown — vendor scale factor unconfirmed |
| FalconSensorReadings | `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | `temp_board` | — (undefined, `int16`) | `Celsius.msg` (°C) | ⚠ unknown — vendor scale factor unconfirmed |
| FalconSensorReadings | `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | `temp_det[4]` | — (undefined, `int16`) | `Celsius.msg[4]` (°C) | ⚠ unknown — vendor scale factor unconfirmed |
| FalconSensorReadings | `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | `temp_other[3]` | — (undefined, `int16`) | `Celsius.msg[3]` (°C) | ⚠ unknown — vendor scale factor unconfirmed |
| FalconSensorReadings | `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | `motor_rpm` | rpm (rev/min) | `Hertz.msg` (Hz) | `Hz = rpm / 60` |
| FalconSensorReadings | `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | `galvo_fpm` | fpm (frames/min) | `Hertz.msg` (Hz) | `Hz = fpm / 60` |
| FalconSensorReadings | `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | `galvo_offset_angle_client` | — (undefined) | `Radians.msg` (rad) or `Degrees.msg` (deg) | ⚠ unknown — both are legal units, producer must confirm |
| FalconSensorReadings | `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | `moisture_index[2]` | arbitrary index | `Percent.msg[2]` (%) | ⚠ unknown — index scale undocumented |
| FalconSensorReadings | `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | `window_blockage_index[2]` | arbitrary index | `Percent.msg[2]` (%) | ⚠ unknown — index scale undocumented |
| FalconSensorReadings | `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | `heater_current_ma` | mA | `Amperes.msg` (A) | `A = mA / 1000` |
| FalconStatus | `jen_lidar_falcon_driver_msgs/msg/FalconStatus.msg` | `temp_fpga` | — (undefined, `int16`) | `Celsius.msg` (°C) | ⚠ unknown — vendor scale factor unconfirmed |
| FalconStatus | `jen_lidar_falcon_driver_msgs/msg/FalconStatus.msg` | `temp_adc` | — (undefined, `int16`) | `Celsius.msg` (°C) | ⚠ unknown — vendor scale factor unconfirmed |
| FalconStatus | `jen_lidar_falcon_driver_msgs/msg/FalconStatus.msg` | `temp_board` | — (undefined, `int16`) | `Celsius.msg` (°C) | ⚠ unknown — vendor scale factor unconfirmed |
| FalconStatus | `jen_lidar_falcon_driver_msgs/msg/FalconStatus.msg` | `temp_laser` | — (undefined, `int16`) | `Celsius.msg` (°C) | ⚠ unknown — vendor scale factor unconfirmed |
| FalconStatus | `jen_lidar_falcon_driver_msgs/msg/FalconStatus.msg` | `temp_det[4]` | — (undefined, `int16`) | `Celsius.msg[4]` (°C) | ⚠ unknown — vendor scale factor unconfirmed |
| FalconStatus | `jen_lidar_falcon_driver_msgs/msg/FalconStatus.msg` | `uptime` | — (undefined, `float64`) | `builtin_interfaces/Duration` | 1:1 if already seconds — ⚠ confirm |
| FalconStatusCounters | `jen_lidar_falcon_driver_msgs/msg/FalconStatusCounters.msg` | `power_up_time_in_second` | s (`uint32`) | `builtin_interfaces/Duration` | `sec = value`; `nanosec = 0` |
| FalconStatusCounters | `jen_lidar_falcon_driver_msgs/msg/FalconStatusCounters.msg` | `process_up_time_in_second` | s (`uint32`) | `builtin_interfaces/Duration` | `sec = value`; `nanosec = 0` |
| FalconStatusCounters | `jen_lidar_falcon_driver_msgs/msg/FalconStatusCounters.msg` | `latency_10us_average[6]` | 10 µs ticks | `builtin_interfaces/Duration[6]` | `nanosec = ticks * 10000` |
| FalconStatusCounters | `jen_lidar_falcon_driver_msgs/msg/FalconStatusCounters.msg` | `latency_10us_variation[6]` | 10 µs ticks | `builtin_interfaces/Duration[6]` | `nanosec = ticks * 10000` |
| FalconStatusCounters | `jen_lidar_falcon_driver_msgs/msg/FalconStatusCounters.msg` | `latency_10us_max[6]` | 10 µs ticks | `builtin_interfaces/Duration[6]` | `nanosec = ticks * 10000` |
| FalconStatusCounters | `jen_lidar_falcon_driver_msgs/msg/FalconStatusCounters.msg` | `cpu_percentage` | % (`uint16`) | `Percent.msg` (%) | 1:1 |
| FalconStatusCounters | `jen_lidar_falcon_driver_msgs/msg/FalconStatusCounters.msg` | `mem_percentage` | % (`uint16`) | `Percent.msg` (%) | 1:1 |
| FalconStatusCounters | `jen_lidar_falcon_driver_msgs/msg/FalconStatusCounters.msg` | `netstat_rx_speed_kbps` | kbit/s | bit/s (SI-derived) | `bit/s = kbps * 1000` |
| FalconStatusCounters | `jen_lidar_falcon_driver_msgs/msg/FalconStatusCounters.msg` | `netstat_tx_speed_kbps` | kbit/s | bit/s (SI-derived) | `bit/s = kbps * 1000` |
| FalconStatusCounters | `jen_lidar_falcon_driver_msgs/msg/FalconStatusCounters.msg` | `sys_cpu_percentage[4]` | % (`uint16`) | `Percent.msg[4]` (%) | 1:1 |
| FalconStatusCounters | `jen_lidar_falcon_driver_msgs/msg/FalconStatusCounters.msg` | `lifelong_uptime` | — (undefined) | `builtin_interfaces/Duration` | ⚠ unknown — no unit stated in any form |
| FalconStatusExtended | `jen_lidar_falcon_driver_msgs/msg/FalconStatusExtended.msg` | `timestamp` | — (raw `float64` epoch) | `builtin_interfaces/Time` | `sec = trunc(t)`; `nanosec = round((t - trunc(t)) * 1e9)` |
| Lane | `jen_scene_msgs/msg/Lane.msg` | `left_boundary` | m (implied by REP-103 only) | `geometry_msgs/Point` in m — document it | 1:1 |
| Lane | `jen_scene_msgs/msg/Lane.msg` | `right_boundary` | m (implied by REP-103 only) | `geometry_msgs/Point` in m — document it | 1:1 |
| TriggerLine | `jen_scene_msgs/msg/TriggerLine.msg` | `start` | m (implied by REP-103 only) | `geometry_msgs/Point` in m — document it | 1:1 |
| TriggerLine | `jen_scene_msgs/msg/TriggerLine.msg` | `end` | m (implied by REP-103 only) | `geometry_msgs/Point` in m — document it | 1:1 |
| TriggerZone | `jen_scene_msgs/msg/TriggerZone.msg` | `polygon` | m (implied by REP-103 only) | `geometry_msgs/Point` in m — document it | 1:1 |
| CameraImageParameters | `jen_sr355_alignment_msgs/msg/CameraImageParameters.msg` | `gain` | — (undefined) | dimensionless (document it) | 1:1 if a plain factor — ⚠ confirm not dB |
| LidarAlignmentBFotoLine | `jen_sr355_alignment_msgs/msg/LidarAlignmentBFotoLine.msg` | `distance` | — (undefined) | `Meters.msg` (m) | ⚠ unknown — m vs px unconfirmed |
| LidarAlignmentImage | `jen_sr355_alignment_msgs/msg/LidarAlignmentImage.msg` | `binning` | — (undefined) | dimensionless (document it) | 1:1 |
| LidarAlignmentImageRequest | `jen_sr355_alignment_msgs/msg/LidarAlignmentImageRequest.msg` | `gain` | — (undefined) | dimensionless (document it) | 1:1 if a plain factor — ⚠ confirm not dB |
| LidarAlignmentParameterValue | `jen_sr355_alignment_msgs/msg/LidarAlignmentParameterValue.msg` | `value` | — (undefined, fully generic) | per-parameter unit type | ⚠ unknown — no unit possible without a parameter registry |
| LidarAlignmentTriggerLine | `jen_sr355_alignment_msgs/msg/LidarAlignmentTriggerLine.msg` | `distance` | — (undefined) | `Meters.msg` (m) | ⚠ unknown — m vs px unconfirmed |
| LidarAlignmentTriggerLine | `jen_sr355_alignment_msgs/msg/LidarAlignmentTriggerLine.msg` | `direction` | — (bare `int32`, no enum) | enum constants (unitless) | n/a — needs an enum definition, not a conversion |
| FluentbitCPUCoreMetrics | `jen_system_msgs/msg/FluentbitCPUCoreMetrics.msg` | `p_cpu` | % as `[0.0-100.0]` range | `Percent.msg` (%) | 1:1 (widen `float32` → `float64`) |
| FluentbitCPUCoreMetrics | `jen_system_msgs/msg/FluentbitCPUCoreMetrics.msg` | `p_system` | % as `[0.0-100.0]` range | `Percent.msg` (%) | 1:1 (widen `float32` → `float64`) |
| FluentbitCPUCoreMetrics | `jen_system_msgs/msg/FluentbitCPUCoreMetrics.msg` | `p_user` | % as `[0.0-100.0]` range | `Percent.msg` (%) | 1:1 (widen `float32` → `float64`) |
| FluentbitCPUMetrics | `jen_system_msgs/msg/FluentbitCPUMetrics.msg` | `cpu_p` | % as `[0.0-100.0]` range | `Percent.msg` (%) | 1:1 (widen `float32` → `float64`) |
| FluentbitCPUMetrics | `jen_system_msgs/msg/FluentbitCPUMetrics.msg` | `system_p` | % as `[0.0-100.0]` range | `Percent.msg` (%) | 1:1 (widen `float32` → `float64`) |
| FluentbitCPUMetrics | `jen_system_msgs/msg/FluentbitCPUMetrics.msg` | `user_p` | % as `[0.0-100.0]` range | `Percent.msg` (%) | 1:1 (widen `float32` → `float64`) |
| FluentbitMemoryMetrics | `jen_system_msgs/msg/FluentbitMemoryMetrics.msg` | `mem_free` | kilobytes | **spec gap** — not in unit system | ⚠ needs spec decision (also kB vs KiB is ambiguous) |
| FluentbitMemoryMetrics | `jen_system_msgs/msg/FluentbitMemoryMetrics.msg` | `mem_total` | kilobytes | **spec gap** — not in unit system | ⚠ needs spec decision (also kB vs KiB is ambiguous) |
| FluentbitMemoryMetrics | `jen_system_msgs/msg/FluentbitMemoryMetrics.msg` | `mem_used` | kilobytes | **spec gap** — not in unit system | ⚠ needs spec decision (also kB vs KiB is ambiguous) |
| FluentbitMemoryMetrics | `jen_system_msgs/msg/FluentbitMemoryMetrics.msg` | `mem_used_p` | % as `[0.0-100.0]` range | `Percent.msg` (%) | 1:1 (widen `float32` → `float64`) |
| FluentbitMemoryMetrics | `jen_system_msgs/msg/FluentbitMemoryMetrics.msg` | `swap_free` | kilobytes | **spec gap** — not in unit system | ⚠ needs spec decision (also kB vs KiB is ambiguous) |
| FluentbitMemoryMetrics | `jen_system_msgs/msg/FluentbitMemoryMetrics.msg` | `swap_total` | kilobytes | **spec gap** — not in unit system | ⚠ needs spec decision (also kB vs KiB is ambiguous) |
| FluentbitMemoryMetrics | `jen_system_msgs/msg/FluentbitMemoryMetrics.msg` | `swap_used` | kilobytes | **spec gap** — not in unit system | ⚠ needs spec decision (also kB vs KiB is ambiguous) |
| FluentbitMemoryMetrics | `jen_system_msgs/msg/FluentbitMemoryMetrics.msg` | `swap_used_p` | % as `[0.0-100.0]` range | `Percent.msg` (%) | 1:1 (widen `float32` → `float64`) |
| FluentbitThermalZone | `jen_system_msgs/msg/FluentbitThermalZone.msg` | `temp` | °C (documented) | `Celsius.msg` (°C) | 1:1 (widen `float32` → `float64`) |
| ObjectTrack3D | `jen_vision_msgs/msg/ObjectTrack3D.msg` | `velocity` | — (undefined) | m/s (`geometry_msgs/Vector3`, documented) | ⚠ unknown — m/s vs km/h unconfirmed, see the km/h rows below |
| ObjectTrack3D | `jen_vision_msgs/msg/ObjectTrack3D.msg` | `confidence_speed` | — (undefined) | `Percent.msg` (%) | ⚠ unknown — no range stated |
| ObjectTrack3D | `jen_vision_msgs/msg/ObjectTrack3D.msg` | `confidence_pose` | — (undefined) | `Percent.msg` (%) | ⚠ unknown — no range stated |
| ObjectTrack3D | `jen_vision_msgs/msg/ObjectTrack3D.msg` | `confidence_dimension` | — (undefined) | `Percent.msg` (%) | ⚠ unknown — no range stated |
| PlateRecognition | `jen_vision_msgs/msg/PlateRecognition.msg` | `vrn_confidence` | — (undefined, `uint8`) | `Percent.msg` (%) | ⚠ unknown — no range stated |
| PlateRecognition | `jen_vision_msgs/msg/PlateRecognition.msg` | `country_confidence` | — (undefined, `uint8`) | `Percent.msg` (%) | ⚠ unknown — no range stated |
| PlateRecognition | `jen_vision_msgs/msg/PlateRecognition.msg` | `character_height` | pixels (documented) | **spec gap** — not in unit system | ⚠ needs spec decision |
| PlateRecognition | `jen_vision_msgs/msg/PlateRecognition.msg` | `plate_angle_deg` | deg | `Degrees.msg` (deg) | 1:1 |
| TriggerEvent | `jen_vision_msgs/srv/TriggerEvent.srv` | `speed` | **km/h** (documented) | `MetersPerSecond.msg` (m·s⁻¹) | `m/s = km/h / 3.6` |
| ValidateObject | `jen_vision_msgs/action/ValidateObject.action` | `speed` | **km/h** (documented) | `MetersPerSecond.msg` (m·s⁻¹) | `m/s = km/h / 3.6` |

## Summary by conversion class

Each row falls into exactly one class; the classes total 96.

| class | rows | meaning |
|---|---|---|
| `1:1` — type change only | 32 | value already numerically correct; wrap it in a unit message |
| `1:1` — pending confirmation | 6 | almost certainly 1:1, but the current unit was never written down |
| real arithmetic conversion | 15 | an unambiguous formula exists |
| unknown | 28 | current unit undetermined — must be confirmed with the producing node |
| **spec gap** (bytes / pixels) | 14 | the Shire unit system does not cover these at all |
| needs an enum, not a unit | 1 | `LidarAlignmentTriggerLine.direction` |

**48 of the 96 rows carry an open question** (28 unknown + 6 pending
confirmation + 14 spec gap). None can be actioned by editing `.msg` files alone
— they are blocking input for SHIRE-1590, not implementation work.

The other **47 rows** (32 `1:1` + 15 with a real formula) are ready to implement
once the unit-message package from §0 of the report exists.

The 29 rows that are physical quantities with an undetermined unit are broken
out separately in [1590-outofconcept.md](1590-outofconcept.md).
