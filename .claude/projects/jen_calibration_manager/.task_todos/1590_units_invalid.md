# 1590 — invalid unit fields

Split out of `1590_units.md`. Target: SI, except temperature in °C; `deg` and `%` allowed; time in `builtin_interfaces/Time`/`Duration`; speed in m/s.

## ❌ Invalid — must change

Conversions: header-only `jen-static-conversion` (`jen_static_conversion/UnitConversion.hpp`).
`Duration`/`Time` are `builtin_interfaces::msg::Duration`/`Time`.

| Message | Field | Current unit | Should be | | Conversion (`jen::conversion`) |
|---|---|---|---|---|---|
| **jen_buffer_node_msgs** | | | | | |
| GetItemByTimestamp.srv | threshold_ms | ms millisecond (uint32) | s → `builtin_interfaces/Duration` | ❌ | `toStamp<Duration, unit::Millisecond>` |
| **jen_hal_msgs** | | | | | |
| ClocksStatus | clock_diff_ms | ms millisecond (int64) | s → `Duration` | ❌ | `toStamp<Duration, unit::Millisecond>` |
| **jen_lidar_falcon_driver_msgs** | | | | | |
| FalconSensorReadings | motor_rpm | rpm revolutions per minute | Hz (or rad/s) | ❌ | `convert<unit::Hertz, unit::RevolutionPerMinute>` or `convert<unit::RadianPerSecond, unit::RevolutionPerMinute>` |
| FalconSensorReadings | heater_current_ma | mA milliampere | A | ❌ | `convert<unit::Ampere, unit::Milliampere>` |
| FalconStatusCounters | latency_10us_average / _variation / _max | 10 µs tens of microseconds | s → `Duration` | ❌ | `toStamp<Duration, unit::TenMicroseconds>` |
| FalconStatusExtended | timestamp | not documented (float64) | `Time` | ❌ | `toStamp<Time, unit::Second>` (assumes the float64 is seconds; not confirmed) |
| FalconStatus | uptime | not documented (float64) | `Duration` | ❌ | `toStamp<Duration, unit::Second>` (assumes the float64 is seconds; not confirmed) |
| **jen_vision_msgs** | | | | | |
| ValidateObject.action | speed | km/h kilometre per hour | m/s | ❌ | `convert<unit::MetrePerSecond, unit::KilometrePerHour>` |
| TriggerEvent.srv | speed | km/h kilometre per hour | m/s | ❌ | `convert<unit::MetrePerSecond, unit::KilometrePerHour>` |
| **jen_parameter_msgs** (jen_config_manager_interface) | | | | | |
| DiagnosticMetricConfig | frequency_tolerance | fraction (0.1 = 10 %) | % | ❌ | `convert<unit::Percent, unit::Fraction>` |

## ⚠️ Unit not documented — confirm with the producer

No code in the workspace fills these fields, so the current unit could not be verified.

| Message | Field | Current unit | Should be | |
|---|---|---|---|---|
| **jen_camera_msgs** | | | | |
| CameraParameters | gain_factor | dimensionless factor, linear or dB not documented | dimensionless | ⚠️ |
| **jen_hal_msgs** | | | | |
| PowerSupplyStatus | voltage | not documented | V volt | ⚠️ |
| PowerSupplyStatus | current | not documented | A ampere | ⚠️ |
| **jen_lidar_falcon_driver_msgs** | | | | |
| FalconSensorReadings, FalconStatus | temp_fpga, temp_laser, temp_adc, temp_board, temp_det[] (+ temp_other[]) | not documented (int16) | °C (float64) | ⚠️ |
| FalconSensorReadings | galvo_fpm | "fpm", not documented | Hz | ⚠️ |
| FalconSensorReadings | motor[], galvo[], laser[], galvo_offset_angle_client, moisture_index[], window_blockage_index[] | raw values, not documented | depends on meaning | ⚠️ |
| FalconStatusCounters | lifelong_uptime | not documented | s → `Duration` | ⚠️ |
| **jen_sr355_alignment_msgs** | | | | |
| CameraImageParameters, LidarAlignmentImageRequest | gain | not documented | dimensionless | ⚠️ |
| LidarAlignmentBFotoLine, LidarAlignmentTriggerLine | distance | not documented (float32) | m (float64) | ⚠️ |
| LidarAlignmentLaneMarkers, Markerpoint(s), Polygon2d | Point2D fields | not documented, probably px | px | ⚠️ |
| LidarAlignmentParameterValue | value | depends on the parameter key | per parameter | ⚠️ |
| **jen_vision_msgs** | | | | |
| ObjectTrack3D | confidence_speed / _pose / _dimension | not documented | % | ⚠️ |
| PlateRecognition | vrn_confidence, country_confidence | not documented (uint8) | % | ⚠️ |
