# SHIRE-1695 — MR !1, answers round 3

MR head `7a05712` (pull 2026-11-03 11:48), 10 open threads, pipeline green. You already replied on threads 0, 3
and 4. Below: what is fixed locally and a short reply for every thread that still needs one.

## Fixed locally (not committed)

Working tree of `jen_evidence_rules_manager/jen_speed_enforcement_msgs`. Docker `builder` (4 packages) and `rosdoc`
build, no doc warnings.

```
# action/CheckSpeed.action
jen_vision_msgs/TriggerEvent trigger_event   # Henryk: whole TriggerEvent, replaces the 7 copied fields
bool post_validation
---
EnforcementDecision decision
SpeedEvent speed_event
---

# msg/EnforcementDecision.msg               # threads 3, 4, 10
ERROR = 0, CONFIRM_VIOLATION = 1, DISCARD_EVENT = 2

# msg/SpeedEvent.msg                        # threads 5, 6
MetersPerSecond speed, KmH base_speed_limit, KmH trigger_speed_limit, SpeedRange speed_range
```

- Submodules: `jen_vision_msgs` added (pinned to master `189e6f7`), `jen_scene_msgs` removed (no longer used).
- Dockerfile installs `ros-jazzy-vision-msgs` and copies `jen_vision_msgs` + `jen_buffer_node_msgs`, as the
  `jen_vision_msgs` repo does. Jenkinsfile and README use `git submodule update --init --recursive`.
- README: message table describes what each message holds; units line updated.

**Before posting:** commit and push this first. `.gitmodules`, the submodule add and the `jen_scene_msgs` removal
are already staged; run `git add -A` for the rest.

## Replies

**7 · `srv/CheckSpeed.srv:13` — Jose: at least lane is missing; Henryk: use the whole TriggerEvent**
> Done as Henryk suggested: the goal is now the `TriggerEvent` plus `post_validation`. The lane is not in the
> TriggerEvent, so the speed node takes it from the trigger line (`source_uuid` → `TriggerLine.lane_uuid`).

**8 · `srv/CheckSpeed.srv:1` — post-validation takes time, is a service OK?**
> No, it is an action now. Post-validation can take up to 30 s, and an action does not block ERM and can be
> cancelled.

**9 · `srv/CheckSpeed.srv:2` — post-validation must be flagged per trigger**
> Done: `bool post_validation` in the goal, set by ERM from its `post_validation` configuration. The trigger type
> comes with the TriggerEvent.

**10 · `srv/CheckSpeed.srv:18` — why is `has_condition` a separate flag?**
> Removed. No matching speed condition is now an `ERROR` decision, which ERM reports to the operator.

**5 · `msg/SpeedEvent.msg:6` — vehicle_class is given by the caller**
> Removed.

**6 · `msg/SpeedEvent.msg:4` — m/s in, km/h out (asked to Henryk)**
> Changed to m/s: the input and the post-validation result are both m/s, so the node converts nothing. The km/h
> was left over from before SHIRE-1590. Limits stay km/h, as in the operational profile.

**11 · `README.md:14` — describe what it holds, not the enums**
> Done.

**3 and 4 — you replied "I'll remove it" / "I'll replace it by `ERROR`"**

After the push, a short follow-up so they can be resolved:
> Done.

## Worth knowing before the next review

- `post_validation` is the only field outside the TriggerEvent. If reviewers want it gone too, the speed node
  would need ERM's product configuration.
- The `ObjectDirection` of the TriggerEvent has to be matched against the `DirectionOfTravel` of the speed
  conditions inside the speed node. That is implementation work, not a message change.
