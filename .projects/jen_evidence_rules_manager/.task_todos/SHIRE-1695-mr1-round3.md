# SHIRE-1695 — MR !1, Jose's review of 2026-10-30/31: changes and replies

Supersedes the reply drafts in `SHIRE-1695-mr-comments.md` and `../.design_todos/SHIRE-1695-design-v2-check.md`.
Threads read from the `.gitlab` mirror (pull 2026-11-02, MR head `e23db6e`). Nothing is committed or posted: the
changes sit in the working tree of `jen_evidence_rules_manager/jen_speed_enforcement_msgs`, the replies are for
you to paste.

Links used in the replies:

- [ERM Configuration](https://confluence-sms.group.jenoptik.corp/spaces/SHIR/pages/251826165) — `post_validation`
  switch, "SR355 speed enforcement flowchart"
- [Event Evidence Message](https://confluence-sms.group.jenoptik.corp/spaces/SHIR/pages/215591538) — `EvidenceStatus`
  states
- [Spot Speed Enforcement](https://confluence-sms.group.jenoptik.corp/spaces/SHIR/pages/215593598) — "no rule
  associated", operator notification

## The change in one view

The core of Jose's review: the speed node calls the post-validation, ERM only flags that a trigger needs it. That
makes the call long-running, so the service becomes an action.

```
# action/CheckSpeed.action (was srv/CheckSpeed.srv)
uint64 object_id                        # new: needed for the ValidateObject goal
string source_uuid
string lane_uuid                        # new
builtin_interfaces/Time trigger_time
jen_scene_msgs/DirectionOfTravel direction
string vehicle_class
jen_units_msgs/MetersPerSecond speed
bool post_validation                    # new: set by ERM from the product configuration
---
EnforcementDecision decision
SpeedEvent speed_event                  # has_condition removed
---
                                        # no feedback

# msg/EnforcementDecision.msg
ERROR = 0                               # new, replaces NO_DECISION
CONFIRM_VIOLATION = 1
DISCARD_EVENT = 2                       # TRIGGER_POST_VALIDATION removed

# msg/SpeedEvent.msg
speed, base_speed_limit, trigger_speed_limit, speed_range   # vehicle_class removed
```

Docker `builder` (3 packages) and `rosdoc` build; no doc warnings.

## Replies, one per open thread

### `msg/SpeedEvent.msg:1` — post-validation is called by the speed component

> Agreed, and that makes the call long-running, so `CheckSpeed` is now an action
> (`action/CheckSpeed.action`). ERM sets `post_validation` in the goal for a measured trigger when the product is
> configured for it; the node then sends the `ValidateObject` goal itself and decides on the validated speed.
> `object_id` was added to the goal for that request.

### `srv/CheckSpeed.srv:1` — post-validation takes time, is a service OK?

> No, changed to an action: `ValidateObject` can take up to its 30 s timeout, and an action gives ERM a
> non-blocking call it can cancel. There is no feedback for now: without post-validation the result comes back
> right away, and with it ERM already knows the measurement is done when it receives the measured trigger. Feedback
> can carry the decision on the measured speed if ERM needs it before post-validation ends.

### `srv/CheckSpeed.srv:2` — called for predicted and measured triggers, post-validation must be flagged

> Done: `bool post_validation` in the goal, set by ERM from its `post_validation` configuration
> ([ERM Configuration](https://confluence-sms.group.jenoptik.corp/spaces/SHIR/pages/251826165)). The header
> comment now says the node is called for every TriggerEvent.

### `msg/EnforcementDecision.msg:9` — post-validation is not the speed component's decision

> Agreed, `TRIGGER_POST_VALIDATION` removed. Whether a trigger needs post-validation now comes in with the goal.

### `msg/EnforcementDecision.msg:3` — what is NO_DECISION?

> Removed. The values are now violation, discard or error, as in the flowchart and in `EvidenceStatus`
> ([Event Evidence Message](https://confluence-sms.group.jenoptik.corp/spaces/SHIR/pages/215591538)). `ERROR` is 0,
> so a result that was never filled in reads as an error and never as a violation.

### `srv/CheckSpeed.srv:18` — why is `has_condition` a separate flag?

> Folded into the decision: no speed condition for the lane, direction and class is an `ERROR`, which ERM reports
> to the operator ([Spot Speed Enforcement](https://confluence-sms.group.jenoptik.corp/spaces/SHIR/pages/215593598),
> event without an associated rule). A failed post-validation is an `ERROR` too.

### `srv/CheckSpeed.srv:13` — at least lane is missing

> Added `lane_uuid`, matching `TriggerLine.lane_uuid`: the speed conditions are selected per lane. Also added
> `object_id` for the post-validation request (see the first thread).

### `msg/SpeedEvent.msg:6` — vehicle_class is given by the caller

> Removed. `speed` stays: after post-validation it is the validated speed, which can differ from the one in the goal.

### `msg/SpeedEvent.msg:4` — m/s in, km/h out (question to Henryk)

Jose asked Henryk, so wait for his answer; if you want to add a line:

> With post-validation in the node, the validated speed arrives in m/s from `ValidateObject` too, so keeping
> `SpeedEvent.speed` in m/s would mean no conversion in the node. The limits stay km/h, as in the operational
> profile.

`SpeedEvent.speed` is still `KmH`, as you pushed it. Switching it to `MetersPerSecond` is a one-line change.

### `README.md:14` — describe what the message holds instead of repeating the enums

> Done: the table says what each message holds, the values are only in the `.msg` files.

## Left open

- **Trigger type and confidence thresholds.** The configuration page says the speed node needs the trigger type to
  pick its confidence threshold. The goal carries neither the type nor a confidence. Add
  `jen_vision_msgs/TriggerEventType` and a class confidence only when it is decided that the node applies them.
- **Lane resolution.** ERM fills `lane_uuid` from the trigger line in the scene; an empty `lane_uuid` (line without
  a lane) would end as `ERROR` unless a condition covers all lanes.
- The rename `SpeedEvent` → `SpeedEnforcement` (to match `Evidence.msg`) is still unasked.
