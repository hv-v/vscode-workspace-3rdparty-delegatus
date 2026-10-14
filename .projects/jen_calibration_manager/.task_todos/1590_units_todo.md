# 1590 — fields left for the conversion library

`jen_unit_conversion_lib` cannot convert these yet: it has no `Duration`/`Time` output, no temperature and no
per-minute frame frequency. Each place carries `TODO: add <field> to conversion lib, <unit>`. Paths are relative
to `jen-shire-app-repos/`.

| Field | Target unit | Files with the TODO |
|---|---|---|
| `clock_diff_ms` | Duration | `jen_hal_msgs/msg/ClocksStatus.msg` in `jen_metrics_monitor`, `jen_foxglove_bridge` (the sender is outside these repos) |
| `latency_average`, `latency_variation`, `latency_max` | Duration (already sent as float64 seconds) | `FalconStatusCounters.msg` in `jen_lidar_falcon_driver`, `jen_foxglove_bridge` |
| `timestamp` | Time (source is `ts_start_us`, µs) | `StatusConverter.cpp`, `FalconStatusExtended.msg` in `jen_lidar_falcon_driver`, `jen_foxglove_bridge` |
| `uptime` | Duration | `StatusConverter.cpp`, `FalconStatus.msg` in `jen_lidar_falcon_driver`, `jen_foxglove_bridge` |
| `temp_*` (FalconStatus, FalconSensorReadings) | °C (source is tenths of °C) | `jen_lidar_falcon_driver/src/falcongateway/src/converter/StatusConverter.cpp` |
| `galvo_fpm` | Hz (source is frames per minute × 1000) | `jen_lidar_falcon_driver/src/falcongateway/src/converter/StatusConverter.cpp` |
