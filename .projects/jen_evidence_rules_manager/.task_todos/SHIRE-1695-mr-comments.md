# SHIRE-1695 — MR review threads and draft replies

> **2026-10-30:** the draft replies and the prepared change below are superseded by
> `../.design_todos/SHIRE-1695-design-v2-check.md`, which rechecks the messages against the updated design.

Threads read from the `.gitlab` mirror (pull 2026-10-29). Comments are paraphrased; the full text is in
`.gitlab/.mr/shire/interfaces/jen_speed_enforcement_msgs/1.json` and `.gitlab/.mr/shire/jen_evidence_rules_manager/3.json`.
Nothing here has been posted — copy the replies into GitLab yourself.

## `jen_speed_enforcement_msgs` !1 — 2 open threads

### Thread 1, `msg/SpeedEvent.msg:1` — Jose, then Zach

- **Jose:** this needs to be an action or a service; post-validation suggests an action, to be checked.
- **Zach:** at least a service. ERM calls a service on the speed enforcement node; post-validation is handled
  separately by ERM, since ERM knows whether post-validation is needed and whether speed is processed at all
  (priority, e.g. speed on green).

**Change prepared:** `srv/CheckSpeed.srv`. Request: `source_uuid`, `trigger_time`, `direction`, `vehicle_class`,
`speed`. Response: `has_rule` and a `SpeedEvent`. `SpeedEvent` keeps only the speed metadata for the evidence.

**Draft reply:**

> Changed to a service, `CheckSpeed.srv`, following Zach's split: ERM receives the TriggerEvent, calls `CheckSpeed`
> on the speed enforcement node, and owns post-validation. The check itself is a synchronous rule lookup, so a
> service fits; the long-running part (the `ValidateObject` action, up to 30 s) stays on the ERM side. After
> post-validation ERM calls `CheckSpeed` again with the validated speed, which matches the design ("checked again
> when sending for post-validation"). @jose.roquette, if you still see a case where speed enforcement itself has to
> wait on something, an action is a drop-in change of the same request/response, so I'd keep it a service until
> such a case shows up.
>
> `SpeedEvent` is now the response payload: speed, base and trigger limit, violation and `SpeedRange`. The response
> also carries `has_rule`, so ERM can notify the operator when no rule covers the event.

### Thread 2, `README.md:7` — Jose

- **Jose:** ERM receives the TriggerEvent and makes a request to spot speed to check speed limits; spot speed does
  not receive the TriggerEvent directly.

**Change prepared:** the README describes that flow, and the request carries only the fields the check needs, not
the TriggerEvent.

**Draft reply:**

> Agreed, fixed in the README. The request carries only what the check needs (trigger line, time, direction,
> vehicle class, speed); the TriggerEvent itself stays with ERM.

## `jen_evidence_rules_manager` !3 — threads touching SHIRE-1695

These are on the SHIRE-1660 MR, not on SHIRE-1695 code, but they decide where AC2 goes.

- **Jose (`speed_enforcement.hpp:18`):** SpeedEnforcement is a separate node by design; the class can be approved to
  move forward, but **must** be removed in SHIRE-1719. Zach: the implementation is mostly to be thrown away and does
  not unblock further tickets.
- **Zach (`speed_enforcement.cpp:70`):** most `ValidateObject` statuses make no functional difference; could be
  SUCCESS/FAIL, with the detailed logging left to post-validation.
- **Zach (`evidence_rules_manager.cpp:64`):** the `onResult` callback only logs; why is it needed?

**Consequence for SHIRE-1695:** the manager-side change on local branch `SHIRE-1695-speed-event` (publishes a
`speed_event` topic from the temporary `SpeedEnforcement` class) contradicts both reviews: the interface is now a
service, and the class is to be removed. **Recommendation: do not open an MR for it.** AC2 ("implement … in Speed
Enforcement component") goes with SHIRE-1719, where the node serves `CheckSpeed` and ERM becomes its client — this
is also what Jose's Jira comment on SHIRE-1695 says.

The two Zach threads on `speed_enforcement.cpp` / `evidence_rules_manager.cpp` belong to SHIRE-1660 (Inna's MVP),
not to this ticket; nothing in SHIRE-1695 needs to answer them.

## Questions the reviewers may still raise

- **`trigger_time` in the request:** limits depend on time (operational profile schedule, VMS history, grace
  period), so the check needs the time of the measurement. Drop it if limits are resolved before the call.
- **`speed` is in both the request and `SpeedEvent`:** `SpeedEvent` is the evidence metadata and the ticket lists
  travel speed in it; it can be dropped from the response if ERM keeps its own copy.
- **`has_rule`:** needed now that a response always comes back. The alternative is a status enum, if more outcomes
  than "rule / no rule" are expected.
- **`DirectionOfTravel` for the direction:** the rule configuration's vocabulary (BOTH / TOWARDS / AWAY). ERM maps
  `ObjectDirection` UNKNOWN to BOTH when filling the request.
