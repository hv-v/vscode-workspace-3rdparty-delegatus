# jen_prediction_trigger

ROS2 node that generates predicted and measured trigger events from object tracks. It feeds the tracker
output and the Scene's trigger lines into libalgo's `TriggerLines`, then reports crossings as
`TriggerEvent` service calls and lost tracks on a dedicated topic. Predictions leave ahead of the actual
crossing so downstream sensors can act in time despite pipeline latency.

## ROS interface

### Subscriptions
| Topic (param) | Type | Notes |
|---|---|---|
| `msg_topic_tracking` | `jen_vision_msgs/ObjectTrack3DArray` | tracker output, consumed verbatim |
| `msg_topic_scene` | `jen_scene_msgs/Scene` | trigger lines; `transient_local` (latched) |
| `msg_topic_class_mapping` | `jen_vision_msgs/ObjectClassMappingArray` | sensor-to-customer class mapping; `transient_local`. Unmapped classes drop the event and raise a diagnostics error |
| tf2 | — | transform from each trigger line's `frame_id` to the tracking frame |

### Service Server
| Service (param) | Type | Notes |
|---|---|---|
| `srv_trigger_event_export` | `std_srvs::srv::Empty` | Saves internally recorded trigger events received from libalgo to a file: /ros2_ws/TriggerEvents.json Copy this file from the container to the host file system: `kubectl cp <namespace>/<pod>:/ros2_ws/TriggerEvents.json TriggerEvents.json`|

### Service clients
| Service (param) | Type | Notes |
|---|---|---|
| `srv_trigger_event` | `jen_vision_msgs/TriggerEvent` | one call per predicted or measured trigger; events are dropped (and counted) while the service is unavailable |

### Publications
| Topic (param) | Type |
|---|---|
| `msg_topic_object_lost` | `jen_vision_msgs/ObjectLost` |
| `/diagnostics` | `diagnostic_msgs/DiagnosticArray` (via `diagnostic_updater`) |

## Parameters

Delivered via `jen_config_manager`; see [chart/values.yaml](chart/values.yaml).

| Parameter | Type | Default | Purpose |
|---|---|---|---|
| `msg_topic_tracking` / `_scene` / `_class_mapping` / `_object_lost`, `srv_trigger_event` | string | — | topic and service names |
| `discardTrackingDataByAge` / `maxTrackingDataAge` | bool / double(s) | false / 0 | drop tracking input older than the threshold |
| `maxInputGap` | double(s) | 0 | warn when no tracking data arrives within this gap (0 disables) |
| `predictionLookahead` | double | 0.5 | prediction horizon; seconds or meters per `predictionLookaheadMode` |
| `predictionLookaheadMode` | string | `time` | `time` or `distance` |
| `triggerPipelineLatencyOffset` | double(s) | 0 | added to the time horizon so predictions cover downstream latency; predictions closer to the crossing than this are dropped as unactionable |
| `predictionResendInterval` | double(s) | 0 | re-send a pending prediction after this interval; 0 sends once per object and line |
| `exportTriggerEvents` | bool | false | Turn on/off internal recording of trigger events received from libalgo. Can be updated during runtime. |

## Behaviour notes

- Trigger events carry geometry in the tracking frame (`header.frame_id`); line endpoints are transformed
  into it before being handed to libalgo. A line whose transform is unavailable keeps its id slot and is
  added once the transform appears, without disturbing the already active lines.
- A Scene `TriggerLine` expands into one libalgo line per direction and trigger position;
  `DirectionOfTravel BOTH` and `TriggerPosition BOTH` therefore multiply. `TriggerEvent.source_uuid` is the
  configured line's uuid and `direction` follows from the expansion, never `UNKNOWN`.
- Disabled scenes, lines, and lines of disabled lanes are excluded (the `enabled` cascade from the
  interface definitions).
- `TriggerZone`s are not supported by libalgo and are ignored with a warning.
- libalgo emits `PREDICTED_CROSSING` on every frame within the horizon; only the first is sent per
  (object, trigger line) unless `predictionResendInterval` re-arms it. The recipient schedules on
  `trigger_time`; a following MEASURED call reports the actual crossing.
- `ObjectLost.last_seen_timestamp` is the stamp of the last tracking frame that contained the object.

## Build and test

```bash
colcon build --packages-select jen_prediction_trigger
colcon test --packages-select jen_prediction_trigger
```

The `adapter` (ROS<->libalgo conversions) and `TriggerState` (id widening, seen-times, prediction dedupe)
modules are pure and unit-tested independently (`MessageAdapterTest`, `TriggerStateTest`).
