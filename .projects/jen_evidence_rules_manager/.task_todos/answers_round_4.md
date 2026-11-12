# SHIRE-1695 — MR !1, answers round 4

MR head `b91967a` (pull 2026-11-09), 1 open thread (the km/h one, waiting for Henryk). The comment below came in
outside the diff threads, so it is not in the mirror; replies follow its points in order.

## Fixed locally (not committed)

`action/CheckSpeed.action` has a feedback part now: the decision and the speed metadata of the measured speed, sent
once before the post-validation starts. Docker `builder` (4 packages) and `rosdoc` build, no doc warnings.

```
---                                   # feedback
EnforcementDecision decision
SpeedEvent speed_event
```

## Replies

**Without feedback, is it basically a service? How do we trigger the images before post-validation ends?**
> Right, without feedback it is basically a service. The images don't wait for the post-validation: they are
> requested ahead on the prediction, once we get feedback that the vehicle is probably a violator. So we need an
> immediate feedback and then the final result that confirms or discards the event, and an action covers both. Added
> the feedback: the node sends its decision on the trigger speed right away, and the result carries the final decision
> (after the post-validation, when it is requested).

Follow-up from the reviewer: the images are requested ahead on the prediction **if the feedback says the vehicle is
probably a violator**, so the feedback must be immediate and the result confirms or discards. Reply:
> Agreed, thanks. Updated the comments in `CheckSpeed.action` to say exactly that: the feedback is the immediate
> decision on the trigger speed, and `CONFIRM_VIOLATION` there means "probably a violator, request the images ahead".
> The result confirms or discards the event, after the post-validation when it is requested.

Checked 2026-11-09 against Capture Manager v16 (images requested ahead, cancellable), ERM Configuration v26
(`realtime_photo_mode`, SR355 speed flowchart text) and Event Evidence Message v16 (`STATE_PROGRESS` "when
measurement is done" before the post-validation result). No documented flow makes an image wait for the
post-validation.

**SpeedEvent will grow; forward the `operational_profile_uuid` to ERM later.**
> Added `operational_profile_uuid` to `SpeedEvent`, taken from the `GetSpeedConditions` response (Henryk's reply on
> `SpeedEvent.msg:4`). The conditions can follow when they are needed for documentation.

**Why is the speed in m/s and not km/h like the rest?**
> The Unit System page says speeds are communicated in m/s as far into the chain as possible, and the input
> (`TriggerEvent.speed`) and the post-validation result are both m/s already. The limits are km/h only because
> `jen_operational_profile_msgs` still uses `KmH`. I asked in the thread on `SpeedEvent.msg:4` whether the profile
> should move to m/s; then all speeds in `SpeedEvent` would be m/s.

Link: [Units of measurement for the Shire and ROS messages](https://confluence-sms.group.jenoptik.corp/spaces/SHIR/pages/215604632),
"Measurements of speed".

**Returning the speed is good, it can change in post-validation.**
> Yes, that is why it stays in the result.

**The class can change in post-validation too. Add it to SpeedEvent later?**
> Yes. `ValidateObject` returns only the speed today, so I'd add `vehicle_class` to `SpeedEvent` together with the
> post-validation change that returns a class.

## Pipeline

Pipeline 30687 on `b91967a` failed in the Jenkins job `jenkinsci/mr-merge`. Its log is on Jenkins, which the mirror
cannot fetch, so check it in the browser. Locally the same `b91967a` content builds in Docker. One difference from
before: the Jenkinsfile now runs `git submodule update --init --recursive`, which also clones
`jen_vision_msgs/jen_buffer_node_interface/jen_logging`; if the Jenkins agent cannot access that repo, that is the
failure.
