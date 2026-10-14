# Jira ticket draft — camera info data flow

| field | value |
|---|---|
| Project | SHIRE |
| Type | Improvement |
| Summary | Improve the SetCameraInfo data flow between jen_calibration_manager and jen_sc_camera_driver |
| Components | jen_calibration_manager, jen_sc_camera_driver, shire-sr355 |
| Links | relates to SHIRE-1619, SH-1661, SHIRE-1226 |
| Labels | calibration, camera, reliability |

Built section by section. Done: 1. How it works now (with Roles). 2. What could go wrong. 3. Acceptance criteria.

Description — Jira wiki markup, paste as is:

```
h2. How it works now

*Roles:* the camera driver is the service server. Its {{CameraInfoManager}} advertises {{/<nodeName>/set_camera_info}} ({{sensor_msgs/srv/SetCameraInfo}}) and waits to be called. The calibration manager is the client: it calls that service to push the intrinsics into the driver. The driver cannot ask for calibration. It only receives it when the calibration manager calls it.

*Source:* config_manager holds the intrinsics in the calibration manager's {{camera_info_static}} and {{camera_info}} parameters. Each one is a YAML string: a list of pairs, and each pair has a target {{service_name}} and a {{sensor_msgs/CameraInfo}}. SR355 uses only {{camera_info_static}}, with one pair per camera (left and right).

*Trigger:* the calibration manager sends intrinsics only from its post-set parameter callback, that is, when {{camera_info_static}} or {{camera_info}} is set. That happens at startup, while the parameters are loaded from config_manager, and again whenever config_manager changes one at runtime. Nothing else triggers a send: there is no send after startup completes, no timer, and no reaction to a driver appearing or restarting.

*Send:* on each trigger, the calibration manager parses the parameters again and sends the whole list from the parameter that changed, one {{SetCameraInfo}} call per pair to {{pairs[].service_name}}. For each pair it creates a client on first use and waits up to 200 ms for the service. If the service is not there, it skips the pair. Otherwise it sends the request asynchronously and only checks the response for {{success = false}}. There are no retries and no timeouts, and no acknowledgement is stored. Validation results do not change what is sent.

*Receive (camera driver):* the service name comes from the driver's {{nodeName}} (for example {{/jen_sc_camera_driver_left/set_camera_info}}), not from its {{camera_id}}. The service is up before the hardware is initialised. A request replaces the calibration in memory, which is then saved to a file inside the container and lost on restart. The response's {{success}} reflects that file save.

*Use (camera driver):* the driver counts as calibrated when {{k[0] != 0}}. Until then it rejects every image goal. Every published image carries the calibration the driver holds at publish time, and the pushed {{frame_id}} becomes the image's {{frame_id}}.

h3. What could go wrong

* *Driver starts after the calibration manager* (slow hardware init, image pull, late config_manager): the single send finds no service and is never repeated. The camera stays uncalibrated and rejects every image.
* *Driver restarts* (crash, OOM, failed hardware init, pod rescheduled): the driver only receives calibration when the calibration manager calls its {{set_camera_info}} service. It cannot ask for it. The restarted driver starts without calibration, and the calibration manager does not notice the restart, so it does not send again. The camera rejects every image until {{camera_info_static}} is set again or the calibration manager is restarted.
* *Driver is up but not yet discovered within 200 ms*: it is treated as missing and skipped. The camera stays uncalibrated.
* *{{camera_info_static}} is applied before the {{diagnostics.health}} parameter at startup*: the callback, which also reads that parameter, fails and sends nothing to any camera, even if every driver is up.
* *{{camera_info_static}} changes at runtime while a driver is down*: that driver misses the update and later comes back uncalibrated.
* *{{service_name}} does not match the driver's {{nodeName}}* (typo, rename, namespace): this looks exactly like "driver not up yet", so the camera is never calibrated.
* *Intrinsics are invalid* (for example fx ≤ 0, or a degenerate {{P}}): they are still sent, the driver accepts anything with {{k[0] != 0}}, and images are published with the wrong calibration.
* *One field in the YAML is malformed*: the whole update is dropped, and the old intrinsics stay active without any signal.
* *A camera is removed, or the list is emptied*: the change is ignored, and the old calibration stays.
* *Driver stops answering after receiving the request*: there is no timeout, so the delivery state stays unknown.
* *Driver pod gets a read-only filesystem*: the calibration is applied, but it is reported as failed because the file save fails.

h2. Acceptance criteria

These criteria describe the behaviour we expect, not a particular implementation. Either a latched topic or a service with retries is acceptable, as long as every criterion holds.

*Delivery*
* *Late driver:* a driver that starts after the calibration manager is calibrated within 5 s of becoming reachable, without any manual action.
* *Driver restart:* a restarted driver is calibrated again within 5 s, without restarting the calibration manager or setting {{camera_info_static}} again.
* *Startup order:* at startup every configured camera is calibrated, whatever the order in which config_manager applies the parameters.
* *Runtime change:* a change of {{camera_info_static}} reaches every driver, including one that was down at the time of the change, once it is back.
* *No hanging requests:* every request has a timeout. A driver that does not answer is retried, not forgotten.

*Data*
* *Invalid intrinsics are not sent* (fx or fy ≤ 0, a degenerate {{P}}, {{P}} inconsistent with {{K}}). The reason is reported for that camera.
* *Malformed YAML is rejected when it is set:* the parameter update fails, so the parameter value and the active calibration never differ.
* *Removing a camera, or emptying the list, takes effect.*
* *The driver's response reflects whether the calibration was applied*, not whether the file was saved.

*Visibility*
* *The calibration manager reports each camera's delivery state* (delivered, pending, or failed with a reason). A camera that has not received the current calibration raises WARN or ERROR. It is never reported as OK.
* *A {{service_name}} that never becomes reachable is reported by name*, with how long it has been missing.

*Verification*
* *Automated tests cover:* a driver that starts late, a driver restart, every startup parameter order, invalid intrinsics, malformed YAML, and a driver that does not answer.
* *{{nudge_camera_info.py}} is no longer needed* to calibrate a camera on SR355.
```
