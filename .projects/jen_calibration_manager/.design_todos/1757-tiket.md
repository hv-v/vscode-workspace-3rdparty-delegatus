h3. How it works:

*Config Manager* config_manager holds the intrinsics in the calibration manager's {{camera_info_static}} and {{camera_info}} parameters. Each one is a YAML string: a list of pairs, and each pair has a {{service_name}} and a {{sensor_msgs/CameraInfo}}.

*Calibration Manager* The calibration manager sends intrinsics only from its post-set parameter callback, that is, when {{camera_info_static}} or {{camera_info}} is set. That happens at startup, while the parameters are loaded from config_manager, and again whenever config_manager changes one at runtime. Nothing else triggers a send: there is no send after startup completes, no timer, and no reaction to a driver appearing or restarting. 

*Send:* The calibration manager parses the parameters again and sends the whole list from the parameter that changed, one {{SetCameraInfo}} call per pair to {{pairs[].service_name}}. For each pair it creates a client on first use and waits up to 200 ms for the service. If the service is not there, it skips the pair. Otherwise it sends the request asynchronously and only checks the response for {{success = false}}. There are no retries and no timeouts

*Receive (camera driver):* {{CameraInfoManager}} serves {{~/set_camera_info}}, so the service name comes from the driver's {{nodeName}} (for example {{/jen_sc_camera_driver_left/set_camera_info}}), not from its {{camera_id}}. The service is up before the hardware is initialised. A request replaces the calibration in memory, which is then saved to a file inside the container and lost on restart. The response's {{success}} reflects that file save.

h3. What could go wrong:

* *Driver starts after the calibration manager* the single send finds no service and is never repeated. The camera stays uncalibrated and rejects every image. ( Driver is up but not yet discovered within 200 ms)

* *Driver restarts* The calibration is lost with the container, and nothing sends it again. Same result, until someone restarts the calibration manager.

* *Driver stops answering after receiving the request*: there is no timeout, so the delivery state stays unknown.
* *Driver pod gets a read-only filesystem*: the calibration is applied, but it is reported as failed because the file save fails.

h3. Acceptance criteria:

* *Driver starts after the calibration manager:* the driver receives its calibration within the *delivery window* after its {{set_camera_info}} service becomes reachable. This holds however long after the calibration manager the driver starts, and also when service discovery takes longer than 200 ms.

* *Driver restarts:* a restarted driver receives its calibration again within the *delivery window*, without restarting the calibration manager and without setting {{camera_info_static}} or {{camera_info}} again.

* *Driver stops answering after receiving the request:* every {{SetCameraInfo}} request has a timeout. When it expires, the delivery is reported as failed for that camera and is sent again. The delivery state of a camera is never unknown.

* *Driver pod gets a read-only filesystem:* a calibration that the driver has applied is reported as successful, even when the file cannot be saved.

* *Tests:* automated tests cover each of the four cases above: a driver that starts late, a driver that restarts, a driver that does not answer, and a driver that cannot save the file.

*Delivery window:* the longest time allowed between the moment a driver's {{set_camera_info}} service becomes reachable and the moment that driver holds the current calibration. It is one configurable value for all cameras. Its concrete value is chosen during implementation, from how long the system may wait for a camera after start. It is not the request timeout: the request timeout limits a single {{SetCameraInfo}} call and must be shorter, so that a call that got no answer can be sent again inside the delivery window.
