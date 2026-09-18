# 1590 — unit audit of jen-interfaces-modules

Target: SI, except temperature in °C. `deg` and `%` are allowed. Time goes in
`builtin_interfaces/Time` or `Duration`. Speed is in m/s.

This file lists only the compliant fields (✅).

| Message | Field | Current unit | Should be | |
|---|---|---|---|---|
| **jen_accelerator_metrics_msgs** | | | | |
| HailoDeviceStatus, JetsonDeviceStatus | temperature_c | °C degrees Celsius | °C | ✅ |
| HailoDeviceStatus, JetsonDeviceStatus, HailoWorkloadStatus | utilization_pct | % percent | % | ✅ |
| HailoDeviceStatus, JetsonDeviceStatus | power_w | W watt | W | ✅ |
| JetsonDeviceStatus | mem_used_pct | % percent | % | ✅ |
| **jen_buffer_node_msgs** | | | | |
| ItemHeader, GetItemByTimestamp, InsertItem | stamp | `Time` | `Time` | ✅ |
| **jen_camera_msgs** | | | | |
| CameraImageGoal | trigger_time / allowed_deviation | `Time` / `Duration` | same | ✅ |
| CameraParameters | exposure_time | `Duration` | `Duration` | ✅ |
| FlashRequest | trigger_time / pulse_duration | `Time` / `Duration` | same | ✅ |
| ImageMetadata | latitude, longitude | deg degree (WGS84 convention) | deg | ✅ |
| ImageMetadata | capture_timestamp, secondary_timestamp | `Time` | `Time` | ✅ |
| **jen_detector_msgs** | | | | |
| LicensePlate | confidence_read / _country / _detection | % percent (0–100) | % | ✅ |
| LicensePlate | characters_rotation_deg | deg degree | deg | ✅ |
| ObjectDetected, Vehicle | confidence_detection / _classification | % percent (0–100) | % | ✅ |
| ObjectDetected, Vehicle | timestamp | `Time` | `Time` | ✅ |
| **jen_hal_msgs** | | | | |
| Temperature | temperature_c | °C degrees Celsius | °C | ✅ |
| **jen_lidar_falcon_driver_msgs** | | | | |
| FalconStatusCounters | power_up_time_in_second, process_up_time_in_second | s second (uint32) | s → `Duration` | ✅ |
| FalconStatusCounters | cpu_percentage, mem_percentage, sys_cpu_percentage[] | % percent | % | ✅ |
| **jen_scene_msgs** | | | | |
| Lane | left_boundary, right_boundary | m metre (world frame) / px pixel (pixel frame) | same | ✅ |
| TriggerLine | start, end | m / px, as above | same | ✅ |
| TriggerZone | polygon | m / px, as above | same | ✅ |
| **jen_sr355_alignment_msgs** | | | | |
| CameraImageParameters, LidarAlignmentImageRequest | exposure | `Duration` | `Duration` | ✅ |
| LidarAlignmentImage | image_time | `Time` | `Time` | ✅ |
| **jen_system_msgs** | | | | |
| FluentbitCPUMetrics | cpu_p, system_p, user_p | % percent (float32) | % | ✅ |
| FluentbitCPUCoreMetrics | p_cpu, p_system, p_user | % percent (float32) | % | ✅ |
| FluentbitMemoryMetrics | mem_used_p, swap_used_p | % percent | % | ✅ |
| FluentbitThermalZone | temp | °C degrees Celsius | °C | ✅ |
| **jen_vision_msgs** | | | | |
| TriggerEvent.srv | bbox_3d, trajectory_3d, trigger_position_3d | m metre | m | ✅ |
| TriggerEvent.srv | sensor_data_time, trigger_time, first_seen_time | `Time` | `Time` | ✅ |
| ObjectTrack3D | bounding_box | m metre | m | ✅ |
| ObjectTrack3D | velocity | m/s metre per second | m/s | ✅ |
| ObjectTrack3D | time_offset | `Duration` | `Duration` | ✅ |
| ObjectLost | last_seen_timestamp | `Time` | `Time` | ✅ |
| PlateRecognition | plate_angle_deg | deg degree | deg | ✅ |
| **jen_parameter_msgs** (jen_config_manager_interface) | | | | |
| DiagnosticMetricConfig | expected_frequency | Hz hertz | Hz | ✅ |
| ScCameraConfig | timing_safety_margin, cancellation_proximity_threshold, imager_preparation_time, flash_ramp_up_time | `Duration` | `Duration` | ✅ |

Fields that break the rules or have no documented unit are in `1590_units_invalid.md`. Fields with no
physical unit (pixels, bytes, bit rates) are outside the scope of this ticket.

The spec also says every unit is float64. The float32 and integer fields marked
✅ above have the right unit but not that type.

No unit fields: jen_calibration_manager_msgs (empty), jen_config_manager_interface
msg/srv, jen_parameter_msgs Example/Student (demo), RtspStream,
ScCameraCalibration, SystemdMonitor, and all enum and ID messages.
