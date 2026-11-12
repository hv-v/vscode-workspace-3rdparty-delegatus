# SHIRE-1695 — MR !1, check round 5

Pull 2026-11-10: MR head `b91967a`, 13 threads, 2 open (`SpeedEvent.msg:4`, `CheckSpeed.action:15`). Pipeline 30687
still failed in Jenkins `mr-merge` (external log). Confluence re-pulled; changed pages relevant here: rule loader
design v13 (SHIRE-1509). Capture Manager v18 only renamed test-image fields.

## Thread by thread

| Thread | Ask | State |
|---|---|---|
| `SpeedEvent.msg:1` | action, post-validation run by the speed node | done: `CheckSpeed` action, `post_validation` in the goal |
| `README.md:7` | ERM receives the TriggerEvent, not the speed node | done |
| `EnforcementAction.msg:1` | rename | done: `EnforcementDecision` |
| `EnforcementDecision.msg:9` | no `TRIGGER_POST_VALIDATION` | done |
| `EnforcementDecision.msg:3` | violation / discard / error | done |
| `SpeedEvent.msg:6` | class is given by the caller | done: removed |
| `SpeedEvent.msg:4` (open) | units, class, `operational_profile_uuid` | local: `operational_profile_uuid` added; units and class stay as Henryk said |
| `CheckSpeed.srv:13` | lane missing, use the whole TriggerEvent | done |
| `CheckSpeed.srv:1` | service vs action | done |
| `CheckSpeed.srv:2` | flag post-validation per trigger | done |
| `CheckSpeed.srv:18` | `has_condition` into the decision | done |
| `README.md:14` | describe, don't repeat enums | done |
| `CheckSpeed.action:15` (open) | feedback | local: immediate feedback + final result; you replied |

## Ticket and Confluence

- Spot Speed Enforcement page (ticket link): speed, limit and trigger limit at the measurement → `SpeedEvent`;
  below/above range → `SpeedRange`; no rule for the event → `ERROR`. All covered.
- ERM Configuration: `post_validation` is a per-sensor ERM switch → matches the goal flag.
- Confidence thresholds per trigger type → the node has `TriggerEvent.type` and `classification` now.

## Fixed locally this round (not committed)

- `README.md`: the action row now mentions the feedback.
- `msg/EnforcementDecision.msg`: `ERROR` also covers a TriggerEvent without speed (`has_speed` false).

Docker `builder` (4 packages) and `rosdoc` pass.

## Reply for the open thread `SpeedEvent.msg:4`

> Thanks. Added `operational_profile_uuid` to `SpeedEvent`, from the `GetSpeedConditions` response; the conditions
> can follow when they're needed for documentation. Units stay as they are, and class stays out until
> `ValidateObject` returns one.

## Open points (not blocking, no change made)

- Rule loader design v13 (REFINING) still shows post-validation as a speed-node rule action. Jose's MR comments and
  the ERM Configuration page make it an ERM flag, as implemented. Worth one line to Inna/Jose if it stays.
- `VehicleTypeSpeedLimit.unlimited`: `SpeedEvent` has no way to say "no limit". Probably a `DISCARD_EVENT` with the
  limits unused; ask if it must be documented.
- `ValidateObject` returns no confidence, so `min_confidence_speed_validation` cannot be applied yet (upstream).
- Pipeline: open the Jenkins log in the browser; local Docker builds pass.
