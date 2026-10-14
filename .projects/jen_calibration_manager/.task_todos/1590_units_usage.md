# 1590 — which shire-apps repositories use the invalid-unit messages

Split out of `1590_units_invalid.md`: covers only its ❌ list; ⚠️ fields and px are ignored.
Generated 2026-09-21 on each repo's default branch (not the commit pinned in the charts):

```bash
./scripts/clone_shire_app_repos.sh      # -> jen-shire-app-repos/, submodules included
./scripts/check_invalid_units.sh        # exit 1 when any repo uses an invalid message
```

Not scanned (access denied): `sw-components/jenapi-ros` (chart `jenapi`), and the
`src/libdoip` submodule of `jen_lidar_falcon_driver`.

"Where": *own code* = the repository's own sources; *submodule* = only through a
submodule it vendors (mostly `jen_buffer_node_interface/jen_buffer_client_lib`).
"Invalid interfaces vendored" counts the ❌ definitions the repo carries, used or not.

## Verdict

| Repository | Uses invalid interface | In its own code | Invalid interfaces vendored |
|---|---|---|---|
| jen_buffer_node | **true** | yes | 2 |
| jen_lidar_falcon_driver | **true** | yes | 5 |
| jen_metrics_monitor | **true** | yes | 2 |
| jen_prediction_trigger | **true** | yes | 4 |
| jen_camera_sim | **true** | no, submodule only | 2 |
| jen_foxglove_bridge | **true** | no, submodule only | 9 |
| jen_lidar_tracker | **true** | no, submodule only | 4 |
| jen_object_detection | **true** | no, submodule only | 2 |
| jen_accelerator_metrics_hailo | false | — | 1 |
| jen_accelerator_metrics_jetson | false | — | 1 |
| jen_calibration_manager | false | — | 1 |
| jen_config_manager | false | — | 1 |
| jen_data_player_prototype | false | — | 0 |
| jen_diagnostic_aggregator | false | — | 0 |
| jen_fluentbit_connector | false | — | 0 |
| jen-generic-device-plugin | false | — | 0 |
| jen_kubernetes_monitor | false | — | 1 |
| jen_sc_camera_driver | false | — | 1 |
| jen_sr355_alignment_gateway | false | — | 1 |
| jen_systemd_monitor | false | — | 1 |
| jen_webserver | false | — | 0 |
| sr355_hardware_control_unit | false | — | 1 |

## ms (millisecond)

| Repository | Where | Interface | Invalid fields referenced | Files |
|---|---|---|---|---|
| jen_buffer_node | own code | jen_buffer_node_msgs/srv/GetItemByTimestamp | `threshold_ms` | jen_buffer_node/include/BufferNode.hpp, jen_buffer_node/src/BufferNode.cpp, jen_buffer_node/test/BufferNodeTest.cpp (+3 more) |
| jen_camera_sim | submodule | jen_buffer_node_msgs/srv/GetItemByTimestamp | `threshold_ms` | jen_buffer_node_interface/jen_buffer_client_lib/include/jen_buffer_client_lib/BufferNodeClient.hpp, jen_buffer_node_interface/jen_buffer_client_lib/src/BufferNodeClient.cpp, jen_buffer_node_interface/jen_buffer_client_lib/test/BufferNodeClientTest.cpp |
| jen_foxglove_bridge | submodule | jen_buffer_node_msgs/srv/GetItemByTimestamp | `threshold_ms` | jen_buffer_node_interface/jen_buffer_client_lib/include/jen_buffer_client_lib/BufferNodeClient.hpp, jen_buffer_node_interface/jen_buffer_client_lib/src/BufferNodeClient.cpp, jen_buffer_node_interface/jen_buffer_client_lib/test/BufferNodeClientTest.cpp (+6 more) |
| jen_lidar_tracker | submodule | jen_buffer_node_msgs/srv/GetItemByTimestamp | `threshold_ms` | jen_buffer_node_interface/jen_buffer_client_lib/include/jen_buffer_client_lib/BufferNodeClient.hpp, jen_buffer_node_interface/jen_buffer_client_lib/src/BufferNodeClient.cpp, jen_buffer_node_interface/jen_buffer_client_lib/test/BufferNodeClientTest.cpp (+3 more) |
| jen_metrics_monitor | own code | jen_hal_msgs/msg/ClocksStatus | — (type only) | jen_metrics_monitor/include/jen_metrics_monitor/components/components.hpp |
| jen_object_detection | submodule | jen_buffer_node_msgs/srv/GetItemByTimestamp | `threshold_ms` | jen_algo_ros/jen_buffer_node_interface/jen_buffer_client_lib/include/jen_buffer_client_lib/BufferNodeClient.hpp, jen_algo_ros/jen_buffer_node_interface/jen_buffer_client_lib/src/BufferNodeClient.cpp, jen_algo_ros/jen_buffer_node_interface/jen_buffer_client_lib/test/BufferNodeClientTest.cpp (+9 more) |
| jen_prediction_trigger | submodule | jen_buffer_node_msgs/srv/GetItemByTimestamp | `threshold_ms` | jen_vision_msgs/jen_buffer_node_interface/jen_buffer_client_lib/include/jen_buffer_client_lib/BufferNodeClient.hpp, jen_vision_msgs/jen_buffer_node_interface/jen_buffer_client_lib/src/BufferNodeClient.cpp, jen_vision_msgs/jen_buffer_node_interface/jen_buffer_client_lib/test/BufferNodeClientTest.cpp |

## rpm (revolution per minute)

| Repository | Where | Interface | Invalid fields referenced | Files |
|---|---|---|---|---|
| jen_lidar_falcon_driver | own code | jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings | `motor_rpm` | src/falcongateway/src/converter/StatusConverter.cpp, src/falcongateway/src/converter/StatusConverter.hpp, src/falcongateway/src/ROSPublisher.cpp (+2 more) |

## mA (milliampere)

| Repository | Where | Interface | Invalid fields referenced | Files |
|---|---|---|---|---|
| jen_lidar_falcon_driver | own code | jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings | `heater_current_ma` | src/falcongateway/src/converter/StatusConverter.cpp, src/falcongateway/src/converter/StatusConverter.hpp, src/falcongateway/src/ROSPublisher.cpp (+2 more) |

## 10 µs (tens of microseconds)

| Repository | Where | Interface | Invalid fields referenced | Files |
|---|---|---|---|---|
| jen_lidar_falcon_driver | own code | jen_lidar_falcon_driver_msgs/msg/FalconStatusCounters | `latency_10us_average`, `latency_10us_variation`, `latency_10us_max` | src/falcongateway/src/converter/StatusConverter.cpp, src/falcongateway/src/converter/StatusConverter.hpp, src/falcongateway/src/ROSPublisher.cpp (+2 more) |

## float64 time, unit undocumented

| Repository | Where | Interface | Invalid fields referenced | Files |
|---|---|---|---|---|
| jen_lidar_falcon_driver | own code | jen_lidar_falcon_driver_msgs/msg/FalconStatusExtended | `timestamp` | src/falcongateway/src/converter/StatusConverter.cpp, src/falcongateway/src/converter/StatusConverter.hpp, src/falcongateway/src/ROSPublisher.cpp (+2 more) |
| jen_lidar_falcon_driver | own code | jen_lidar_falcon_driver_msgs/msg/FalconStatus | `uptime` | src/falcongateway/src/converter/StatusConverter.cpp, src/falcongateway/src/converter/StatusConverter.hpp, src/falcongateway/src/converter/StatusModeConverter.hpp (+3 more) |

## km/h (kilometre per hour)

| Repository | Where | Interface | Invalid fields referenced | Files |
|---|---|---|---|---|
| jen_prediction_trigger | own code | jen_vision_msgs/srv/TriggerEvent | `speed` | jen_prediction_trigger/include/JenPredictionTrigger.hpp, jen_prediction_trigger/src/JenPredictionTrigger.cpp, jen_prediction_trigger/test/JenPredictionTriggerTest.cpp |

## fraction (0.1 = 10 %)

| Repository | Where | Interface | Invalid fields referenced | Files |
|---|---|---|---|---|
| jen_metrics_monitor | own code | jen_parameter_msgs/msg/DiagnosticMetricConfig | `frequency_tolerance` | jen_metrics_monitor/include/jen_metrics_monitor/metric_handler.hpp, jen_metrics_monitor/include/jen_metrics_monitor/metrics_monitor.hpp, jen_metrics_monitor/include/jen_metrics_monitor/threshold_evaluator.hpp (+7 more) |

