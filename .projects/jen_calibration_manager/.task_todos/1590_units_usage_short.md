# 1590 — invalid-unit usage, short version

Short form of `1590_units_usage.md`: at most 3 example files per row, file names only. Full paths and the per-repo verdict are there.

## ms

| Repo | Interface | Invalid field | File examples |
|---|---|---|---|
| jen_buffer_node | jen_buffer_node_msgs/srv/GetItemByTimestamp | `threshold_ms` | BufferNode.hpp, BufferNode.cpp, BufferNodeTest.cpp |
| jen_camera_sim (submodule) | jen_buffer_node_msgs/srv/GetItemByTimestamp | `threshold_ms` | BufferNodeClient.hpp, BufferNodeClient.cpp, BufferNodeClientTest.cpp |
| jen_foxglove_bridge (submodule) | jen_buffer_node_msgs/srv/GetItemByTimestamp | `threshold_ms` | BufferNodeClient.hpp, BufferNodeClient.cpp, BufferNodeClientTest.cpp |
| jen_lidar_tracker (submodule) | jen_buffer_node_msgs/srv/GetItemByTimestamp | `threshold_ms` | BufferNodeClient.hpp, BufferNodeClient.cpp, BufferNodeClientTest.cpp |
| jen_metrics_monitor | jen_hal_msgs/msg/ClocksStatus | — (type only) | components.hpp |
| jen_object_detection (submodule) | jen_buffer_node_msgs/srv/GetItemByTimestamp | `threshold_ms` | BufferNodeClient.hpp, BufferNodeClient.cpp, BufferNodeClientTest.cpp |
| jen_prediction_trigger (submodule) | jen_buffer_node_msgs/srv/GetItemByTimestamp | `threshold_ms` | BufferNodeClient.hpp, BufferNodeClient.cpp, BufferNodeClientTest.cpp |

## rpm

| Repo | Interface | Invalid field | File examples |
|---|---|---|---|
| jen_lidar_falcon_driver | jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings | `motor_rpm` | StatusConverter.cpp, StatusConverter.hpp, ROSPublisher.cpp |

## mA

| Repo | Interface | Invalid field | File examples |
|---|---|---|---|
| jen_lidar_falcon_driver | jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings | `heater_current_ma` | StatusConverter.cpp, StatusConverter.hpp, ROSPublisher.cpp |

## 10 µs

| Repo | Interface | Invalid field | File examples |
|---|---|---|---|
| jen_lidar_falcon_driver | jen_lidar_falcon_driver_msgs/msg/FalconStatusCounters | `latency_10us_average`, `latency_10us_variation`, `latency_10us_max` | StatusConverter.cpp, StatusConverter.hpp, ROSPublisher.cpp |

## float64 time, unit undocumented

| Repo | Interface | Invalid field | File examples |
|---|---|---|---|
| jen_lidar_falcon_driver | jen_lidar_falcon_driver_msgs/msg/FalconStatusExtended | `timestamp` | StatusConverter.cpp, StatusConverter.hpp, ROSPublisher.cpp |
| jen_lidar_falcon_driver | jen_lidar_falcon_driver_msgs/msg/FalconStatus | `uptime` | StatusConverter.cpp, StatusConverter.hpp, StatusModeConverter.hpp |

## km/h

| Repo | Interface | Invalid field | File examples |
|---|---|---|---|
| jen_prediction_trigger | jen_vision_msgs/srv/TriggerEvent | `speed` | JenPredictionTrigger.hpp, JenPredictionTrigger.cpp, JenPredictionTriggerTest.cpp |

## fraction

| Repo | Interface | Invalid field | File examples |
|---|---|---|---|
| jen_metrics_monitor | jen_parameter_msgs/msg/DiagnosticMetricConfig | `frequency_tolerance` | metric_handler.hpp, metrics_monitor.hpp, threshold_evaluator.hpp |
