# SHIRE-1695 — `jen_speed_enforcement_msgs` in the action + state design

A drop-in alternative to the topic-based MR !1, following the SHIRE-1509 Confluence design: the manager sends an
action request with the TriggerEvent, speed enforcement answers with a decision state and the speed metadata.
Not applied anywhere; see `../.design_todos/SHIRE-1695-review.md` for when to use it.

Style follows `jen_vision_msgs` (`ValidateObject.action`, `ObjectDirection.msg`): a comment above each field, enums
as constants plus `uint8 value`.

## `action/EnforceSpeed.action`

```
# Speed enforcement decision for one TriggerEvent, requested by jen_evidence_rules_manager.
# The state is reported to the user in EvidenceStatus.

jen_vision_msgs/TriggerEvent trigger_event
---
# STATE_CONFIRMED, STATE_DISCARDED or STATE_ERROR
EnforcementState state

# Speed metadata of the decision. Not valid when state is STATE_ERROR
SpeedEvent speed_event
---
# STATE_PROGRESS while the decision is pending, e.g. during post-validation
EnforcementState state
```

## `msg/EnforcementState.msg`

```
# State of an enforcement decision

uint8 STATE_PROGRESS = 0
uint8 STATE_CONFIRMED = 1
uint8 STATE_DISCARDED = 2
uint8 STATE_ERROR = 3

uint8 value
```

Redlight and sighting use the same four states on the Confluence page, so this message probably belongs in a shared
interface package once a second enforcement node exists.

## `msg/SpeedEvent.msg`

```
# Speed metadata required for speeding violation documentation

# Travel speed
jen_units_msgs/KmH speed
# Local speed limit at the time of the measurement
jen_units_msgs/KmH base_speed_limit
# Trigger limit at the time of the measurement
jen_units_msgs/KmH trigger_speed_limit

# Whether the speed is below a minimal speed limit or above a maximum
SpeedRange speed_range
```

`msg/SpeedRange.msg` is unchanged.

## What changes against MR !1

| | MR !1 | here |
|---|---|---|
| `object_id`, `source_uuid`, `direction`, `vehicle_class` | in `SpeedEvent` | gone — the goal carries the TriggerEvent |
| `is_violation` | `bool` | gone — `STATE_CONFIRMED` |
| new files | — | `action/EnforceSpeed.action`, `msg/EnforcementState.msg` |
| submodules | `jen_units_msgs`, `jen_scene_msgs` | `jen_units_msgs`, `jen_vision_msgs` (brings `jen_buffer_node_msgs`) |
| `CMakeLists.txt` | msgs only | adds `"action/EnforceSpeed.action"`, `action_msgs` dependency |
