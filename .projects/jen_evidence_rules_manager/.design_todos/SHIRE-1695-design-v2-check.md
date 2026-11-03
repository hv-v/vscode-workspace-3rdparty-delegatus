# SHIRE-1695 — messages checked against the design as of 2026-10-30

> **2026-11-02:** superseded by `../.task_todos/SHIRE-1695-mr1-round3.md` (Jose's second review: the service became an
> action, post-validation moved into the speed node).

Supersedes the message parts of `SHIRE-1695-review.md` and the draft replies in
`../.task_todos/SHIRE-1695-mr-comments.md`. Everything is local: the changes sit uncommitted in the working tree of
`jen_evidence_rules_manager/jen_speed_enforcement_msgs` (branch `SHIRE-1695-speed-event`, base `307bb69`).

## Inputs checked

| input | version | what it settles for the messages |
|---|---|---|
| Confluence 286851081, rule loader and evaluator VERSION 2 (SHIRE-1509) | v2, 2026-10-30 | the node's outcome is an action (confirm / discard / post-validation); limits come from the operational profile; per-stage confidence parameters |
| Confluence 251826165, Evidence Rules Management Configuration | v26, 2026-10-12 | speed enforcement needs the trigger stage to pick its confidence threshold, may return a changed class (`default_class`), and is called again after post-validation |
| Confluence 215591538, Event Evidence Message | v16, 2026-09-28 | `Evidence.msg` carries `SpeedEnforcement[<=1] speed`, copied from the speed component's response |
| Confluence 251825255, Operational Profile Design | v100, 2026-10-30 | conditions per lane, direction and customer class; points to `jen_operational_profile_msgs` |
| `jen_operational_profile_msgs` master `1a102d1` (2026-10-28) | git | limits are `jen_units_msgs/KmH`, direction is `jen_scene_msgs/DirectionOfTravel`, `GetSpeedConditions(timestamp)` |
| `jen_vision_msgs` master `189e6f7` (2026-10-26, SHIRE-1590) | git | `TriggerEvent.speed` and `ValidateObject` speed are now `jen_units_msgs/MetersPerSecond` |
| Confluence 215588435 / 215593598 | v43 / v26 | unchanged: speed component owned by its node, metadata = speed limit, trigger limit, travel speed, min/max range |
| SHIRE-1695, MR !1 threads | 2026-10-29 | no new comments since the last round; both threads still open |

## Changes made (uncommitted)

| file | change | source |
|---|---|---|
| `srv/CheckSpeed.srv` | `speed`: `KmH` → `MetersPerSecond` | matches `TriggerEvent.speed`; no conversion in the manager |
| | response `bool has_rule` → `EnforcementDecision decision` + `bool has_condition` | V2: the outcome is CONFIRM / DISCARD / TRIGGER_POST_VALIDATION; "rule" now means an enforcement-rule override, the "no rule associated" case of the ticket is "no speed condition" |
| `msg/SpeedEvent.msg` | `speed`: `KmH` → `MetersPerSecond` | as above |
| | `+ string vehicle_class` | the class the limits were selected for, part of the evidence metadata |
| | `- bool is_violation` | replaced by `decision` |
| `msg/EnforcementDecision.msg` | new: `NO_DECISION`, `CONFIRM_VIOLATION`, `DISCARD_EVENT`, `TRIGGER_POST_VALIDATION` | V1/V2 action list; named "decision", not "action", so it is not read as a ROS action |
| `CMakeLists.txt`, `package.xml` | new interface files, `builtin_interfaces` dependency | |
| `README.md` | address table in the style of `jen_operational_profile_msgs`, unit note | |

Unchanged and confirmed: `jen_scene_msgs/DirectionOfTravel` (same type as the operational profile), limits in `KmH`
(same as the operational profile), `SpeedRange`, `trigger_time` (the profile is resolved per timestamp).

**Reverted on review (2026-10-30):** the request briefly carried `vision_msgs/ObjectHypothesis classification` and a
`MeasurementStage` (PREDICTION / MEASURE / VALIDATION), both only to apply per-stage confidence thresholds. Nobody
asked for them, classes are plain strings everywhere else (`customer_classes`, `SpeedEvent.vehicle_class`), and
where the thresholds live is still an open discussion on the configuration page. The request keeps
`string vehicle_class`; no `vision_msgs` dependency. If the speed node does get the thresholds, add
`jen_units_msgs/Percent class_confidence` and the stage then.

Docker `builder` and `rosdoc` targets build; the docs build has no warnings.

### Resulting interface

```
# CheckSpeed.srv
string source_uuid
builtin_interfaces/Time trigger_time
jen_scene_msgs/DirectionOfTravel direction
string vehicle_class
jen_units_msgs/MetersPerSecond speed
---
EnforcementDecision decision
bool has_condition
SpeedEvent speed_event

# SpeedEvent.msg
jen_units_msgs/MetersPerSecond speed
string vehicle_class
jen_units_msgs/KmH base_speed_limit
jen_units_msgs/KmH trigger_speed_limit
SpeedRange speed_range
```

## Open decisions (not applied)

1. **Rename `SpeedEvent` → `SpeedEnforcement`.** The evidence message design names the field type
   `SpeedEnforcement[<=1] speed` and says it is copied from the speed component's response. The ticket says
   "speed_event". Recommended: rename, so the manager copies the response into the evidence without a mapping.
2. **Lane.** Speed conditions are per `lane_uuids`; the request carries the trigger line (`source_uuid`). Either
   the speed node resolves `TriggerLine.lane_uuid` from the scene, or the manager sends `lane_uuid`. Ask in review
   which node owns the scene lookup.
3. **Confidence thresholds.** `min_confidence_speed_*` / `min_confidence_class_*` need confidences and a stage;
   `TriggerEvent` has no speed confidence, and the configuration page still debates whether the manager or the
   speed node applies them. Left out of the request until that is decided.
4. **Shared `EnforcementDecision`.** V2 uses the same actions for redlight and sighting. Keep it here until a second
   enforcement node exists, then move it to a shared package.
5. **Mixed units in `SpeedEvent`.** Speed in m/s and limits in km/h are each the unit of their source, so nothing is
   converted on the way. If reviewers want one unit per message, it has to be m/s, and the speed node converts the
   profile limits with `jen_unit_conversion_lib`.

## Replies for MR !1 (replace the earlier drafts)

### Thread `msg/SpeedEvent.msg:1` (Jose: action or service; Zach: service, post-validation in the manager)

> Changed to a service, `CheckSpeed.srv` (`/jen_speed_enforcement/check_speed`), as Zach suggested. The check is
> synchronous: the node resolves the active operational profile for the timestamp and compares the speed against
> its limits ([rule loader V2](https://confluence-sms.group.jenoptik.corp/spaces/SHIR/pages/286851081),
> "Responsibilities distribution"). The result comes back as `EnforcementDecision`: `CONFIRM_VIOLATION`,
> `DISCARD_EVENT` or `TRIGGER_POST_VALIDATION`. These are the design's "actions", renamed so they are not
> confused with ROS actions.
>
> After post-validation the manager calls `CheckSpeed` again with the validated speed and class, because post-validation
> "can change the speed value and/or class"
> ([ERM Configuration](https://confluence-sms.group.jenoptik.corp/spaces/SHIR/pages/251826165), "SR355 speed
> enforcement flowchart").
>
> Open point: [Evidence Rules Management](https://confluence-sms.group.jenoptik.corp/spaces/SHIR/pages/215588435)
> and the V2 intro still have the speed node doing post-validation itself, and V2 calls the request an "action
> request". If that stands, `CheckSpeed` becomes an action with the same request and response. Which one do we
> follow?

Doc check of the claims (2026-10-30): service and "manager runs post-validation" come from Zach's comment, not
from the docs; the docs disagree on who runs post-validation. Re-validation after post-validation, the synchronous
profile check, the action list, per-stage thresholds and the timestamp-based profile are all in the docs.

### Thread `README.md:7` (Jose: the manager receives the TriggerEvent, spot speed does not)

> Fixed: the README describes that flow, and the request carries only the fields the check needs; the
> TriggerEvent stays with the manager.

### Questions to raise yourself in the MR

- Rename `SpeedEvent` to `SpeedEnforcement` to match `Evidence.msg` (decision 1)?
- Who resolves the lane from the trigger line (decision 2)?
- Who applies the confidence thresholds, the manager or the speed node (decision 3)?
