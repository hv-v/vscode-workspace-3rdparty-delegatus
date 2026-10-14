# SHIRE-1619 — how intrinsics reach `jen_sc_camera_driver`

How `jen_calibration_manager` delivers camera intrinsics to `jen_sc_camera_driver`
through `sensor_msgs/srv/SetCameraInfo`, what is weak about it, and the scenarios in
which the flow is unstable or produces wrong results.

**Revisions reviewed**

| repo | revision | note |
|---|---|---|
| `jen_calibration_manager` | `master` @ `7078e8b` | the SR355 umbrella deploys image `0.0.1-dev-46-MR-2-25ab967`; `25ab967` is not in the local clone, so I could not confirm that the deployed image matches this revision |
| `jen_sc_camera_driver` | `master` @ `8763ffe` | the umbrella pins chart `0.0.1-dev-2-MR-13+9274c24`; `9274c24` exists locally and contains the same `CameraInfoManager` code |
| `jen_config_manager_lib_cpp` | submodule @ `4812623` | `initializeFromConfigManager` / `setInConfigManager` |
| `shire-apps` | `master` @ `82a46ee` | `shire-sr355/values.yaml`: the deployed configuration |
| `camera_info_manager` | 5.1.8 (jazzy, inside `jen_sc_camera_driver:latest`) | I confirmed the service name `~/set_camera_info` and the default URL `file://${ROS_HOME}/camera_info/${NAME}.yaml` from the library's strings |

Paths below are relative to the workspace root.

---

## 1. Components and contract

```
 config_manager ──GetNodeParameters (pull at startup)──────▶ jen_calibration_manager
 config_manager ──set_parameters (push on runtime change)──▶   │ post-set callback
                                                               │ onConfigurationReceived
                                                               ▼
                                                   CameraInfoServiceClient::pushCameraInfo
                                                               │ one SetCameraInfo per pair
                                                               ▼
                       /<driver nodeName>/set_camera_info  (camera_info_manager::CameraInfoManager)
                                                               │ in-memory cam_info_
                                                               ▼
               jen_sc_camera_driver: isCalibrated() gates goals; getCameraInfo() is attached to every image
```

| piece | where it is defined | value on SR355 |
|---|---|---|
| intrinsics source | `camera_info_static` / `camera_info` node params (YAML `JenCameraInfo` string) | `shire-apps/shire-sr355/values.yaml:394-434` |
| target service | `pairs[].service_name` in that YAML | `/jen_sc_camera_driver_left/set_camera_info`, `/…_right/…` |
| service actually served | `CameraInfoManager` advertises `~/set_camera_info`, so the name is `/<NODE_NAMESPACE>/<NODE_NAME>/set_camera_info` (`jen_sc_camera_driver/scripts/entrypoint.sh:25` remaps `__node`) | `nodeName: jen_sc_camera_driver_left/right` (`shire-sr355/values.yaml:285,299`) |
| camera identity for topics | `camera_id` (`Config.cpp:46` → `/camera/<camera_id>/…`) | `camera_left`, `camera_right` |
| image `frame_id` | `camera_info.header.frame_id` pushed by the manager (`CameraDriverNode.cpp:197-199`) | `SC4:PCIE:0`, `SC4:PCIE:1` |
| writability | calibration-manager chart: `camera_info*` are `writable: false` (`jen_calibration_manager/chart/values.yaml:70-77`) | the umbrella overrides `camera_info_static` to `writable: true` (`shire-sr355/values.yaml:378-384`) |

Three independent configurations must agree: the driver's `nodeName`, the
calibration manager's `service_name`, and the camera frame in `camera_info` vs the
`tf_static` tree. **Nothing checks any of them against the others.**

---

## 2. Current flow

### 2.1 Calibration manager startup

`jen_calibration_manager/jen_calibration_manager/src/CalibrationManagerNode.cpp`

1. `:69-70` registers the post-set callback `onConfigurationReceived` **before**
   any parameter is declared.
2. `:72-78` declares `diagnostics.health`, `frame_id_pairs` (default `{}`), `tf`,
   `tf_static`, `camera_info`, `camera_info_static` (typed, no default).
3. `:80` `initializeFromConfigManager` pulls the parameters and applies them with
   `node->set_parameters(params)` (`config_manager.hpp:82-108`). The vector is
   built by iterating a `std::unordered_map`, so **the order is unspecified**.
   `rclcpp` sets the parameters one at a time, and the post-set callback runs once
   per parameter.
4. Each callback that carries a calibration parameter runs
   `throwOnUninitializedParams`, which reads **all** parameters, including
   `diagnostics.health` (`:101`). If `diagnostics.health` has not been set yet,
   `get_parameter(...)` throws, the `catch` at `:162-166` logs it, and the callback
   returns **without pushing**.
5. If `camera_info_static` happens to be set after `diagnostics.health`, the
   callback reaches `publishIntrinsicStaticData` (`:177-179`) →
   `pushCameraInfo`.
6. `:81-86`: after `initializeFromConfigManager`, the constructor re-parses
   everything into `manager_`, but it **does not push or publish anything**.
7. `rclcpp::spin` starts. Responses to any requests sent in step 5 are processed
   from here on.

The startup push therefore happens only if the parameter order is right.
`shire-apps/local-dev/nudge_camera_info.py` documents the case where it is wrong
("At startup the post-set callback fires while diagnostics.health is still
declared-but-unset, so onConfigurationReceived aborts before publishing"). The
script exists to re-set `camera_info_static` on the live node by hand.

### 2.2 Runtime update

When config_manager sets `camera_info_static` or `camera_info` through the node's
`set_parameters` service (possible on SR355 because the umbrella makes
`camera_info_static` writable), `onConfigurationReceived` re-parses all four
categories and validates them. For each changed category it calls
`publishIntrinsic*Data` → `resetFailureCount()` + `pushCameraInfo()`.

### 2.3 `CameraInfoServiceClient::pushCameraInfo`

`jen_calibration_manager/jen_calibration_manager/src/CameraInfoServiceClient.cpp:56-81`

For each pair:
- an empty `service_name` records a failure keyed by `frame_id`;
- `clientFor` creates a client the first time a name is seen (`:94-101`);
- `wait_for_service(200 ms)` blocks; if the service is unavailable it records a
  failure and moves on (`:64-67`);
- `async_send_request` sends the request, and the callback records a failure only
  when `success == false` (`:72-79`).

There is no retry, no request timeout, no record of success, and no later attempt.

### 2.4 Camera driver

`jen_sc_camera_driver/camera_driver/src/CameraDriverNode.cpp`

1. `:27` blocking `initializeFromConfigManager` (up to 10 s).
2. `init()` → `initCameraPublisher()` creates `CameraInfoManager(this, camera_id)`
   at `:58`. This advertises `~/set_camera_info` **before** the hardware is
   initialised (`camera_->init` at `:46`; if it throws, the process exits).
3. `handleGoal` rejects every goal while `!isCalibrated()` (`:108-111`). The
   diagnostic task reports `ERROR "Calibration invalid"` (`:64-75`).
4. `set_camera_info` (inside `camera_info_manager`) stores `cam_info_` in memory
   and then saves it to `file://${ROS_HOME}/camera_info/<camera_id>.yaml`. The
   response's `success` is the **result of that save**, not of the update.
5. For every frame, `getCameraInfo()` is read **at publish time**. Its `frame_id`
   becomes the image's `frame_id`, and it is published together with the image
   (`:197-201`).

`isCalibrated()` in `camera_info_manager` only tests `k[0] != 0`. It also
lazy-loads the default URL the first time it is called. In the shipped chart
there is no volume for `/root/.ros`, so the file lives in the container's writable
layer and is gone after every container restart.

---

## 3. Weak parts

Ordered by impact. **C** = can leave a camera unusable, **H** = wrong data
reaches consumers, **M** = degraded robustness or observability, **L** = minor.

### C1 — delivery is event-driven only; startup is order-dependent
- Intrinsics are pushed only from the post-set callback, never from a state that
  is known to be complete (§2.1 steps 4-6).
- Whether the startup push happens depends on the iteration order of an
  `unordered_map` in another library, combined with the read of
  `diagnostics.health` inside `throwOnUninitializedParams`.
- Even when it fires, it is a single 200 ms attempt against a client that was
  created moments before. DDS discovery of a remote service routinely takes
  longer.

### C2 — no re-delivery when a driver (re)starts
- The driver keeps calibration only in memory (the file is in an ephemeral
  layer).
- The manager does not watch the ROS graph, does not retry failed pushes, and has
  no periodic reconciliation.
- A driver that starts after the manager, or restarts after a crash, OOM,
  hardware-init failure or reschedule, **rejects every image request until
  someone restarts the calibration manager or re-sets `camera_info_static`**.

### C3 — fire-and-forget without a success state
- Only failures are recorded (`failures_`). "Never attempted" (the C1 abort) and
  "succeeded" look identical: `set_camera_info_failures = 0`.
- Delivery failures never change the status level. `onHealthUpdateNeeded`
  (`CalibrationManagerNode.cpp:297-301`) only adds key/value entries. The
  level comes from validation and `tf_pairs_available` alone, so a camera that
  never got its intrinsics does not raise WARN or ERROR on the calibration
  manager.
- `resetFailureCount()` clears **all** services on every push, so a static push
  erases failures from a non-static push and vice versa
  (`CalibrationManagerNode.cpp:227,238`).
- Requests have no deadline. If a driver dies after receiving the request, the
  pending entry is never resolved and no failure is reported.

### H1 — validation does not gate the push, and the driver barely validates
- `validateCalibrationData()` (`:171`) only sets diagnostics. `publish*` runs
  unconditionally, so intrinsics that fail `IntrinsicsValidation` are still sent.
- The driver accepts anything with `k[0] != 0`. Negative focal lengths, a
  degenerate `P`, or a `width`/`height` that does not match the sensor are
  published with every image.

### H2 — camera frame vs TF is not checked for static intrinsics
- `FrameIdTopologyValidation::validation` checks `isDefined(transforms,
  msg.cameraInfo)` only (`include/Validations.hpp:169`), never
  `cameraInfoStatic`. It is also skipped when no transforms exist at all
  (`:160-162`).
- On SR355 the cameras are `SC4:PCIE:0/1`, but `tf_static` only defines
  `base_link → camera_link` (`shire-sr355/values.yaml:443-451`). **Images are
  published in frames that the TF tree does not contain**, and diagnostics still
  report `frame_id_topology: ok`.

### H3 — the projection matrix is not checked
- The deployed `p` is `[1,0,0,0, 0,1,0,0, 0,0,1,0]` for both cameras, while `k`
  has `fx ≈ 9218` (`shire-sr355/values.yaml:405-407,425-427`).
- Any consumer that uses `P` (for example `image_geometry::PinholeCameraModel`
  projection or rectification) gets focal length 1.
- No validator compares `P[0:3,0:3]` with `K`.

### H4 — the contract is keyed on the node name, maintained by hand in three places
- `service_name` must equal `/<NODE_NAMESPACE>/<nodeName>/set_camera_info`. The
  camera's own identity (`camera_id`) is not part of the contract.
- The same string is maintained in the driver alias `nodeName`, in
  `camera_info_static`, and in `cameraInfoStub.cameras`.
- A typo or a namespace change produces "service is not available", which looks
  exactly like "driver not started yet".

### M1 — categories can be added to but never cleared
- `CalibrationManager::updateCalibrationData` replaces a category only when the
  new one is non-empty (`src/CalibrationManager.cpp:23-40`).
- `pairs: []` or removing a camera's entry has no effect, and the old pair keeps
  being re-pushed.

### M2 — a parse error aborts the whole update and stays invisible
- A strict-parse failure in any one category throws out of
  `throwOnUninitializedParams`, so **all four** categories keep their previous
  values.
- The parameter itself is already committed (post-set), so the node's parameter
  and the active calibration diverge.
- No diagnostics key reports it. The validation keys describe the old data
  that is still active.
- At startup, an empty string (`Parameter '…' is empty`) throws out of the
  constructor, so the node exits with code 1 and goes into a crash loop.

### M3 — the same camera in `camera_info` and `camera_info_static`
Both lists may target the same service. Which one wins depends on the order of
the parameter callbacks. There is no duplicate check, either within a list or
across lists.

### M4 — `success` reports the file save, not the update
`camera_info_manager` sets `cam_info_` and only then saves the file. Today the
driver runs as root with a writable root filesystem, so the save succeeds. If
the pod gets hardened the way the calibration manager's own chart already is
(dropped capabilities, `readOnlyRootFilesystem`, non-root user), every push will
be reported as a failure even though it was applied. Saving to an ephemeral
layer also gives a false sense of persistence.

### M5 — blocking inside the parameter callback
`wait_for_service(200 ms)` per unavailable camera runs inside the post-set
callback on the single-threaded executor (`main.cpp` → `rclcpp::spin`). For N
absent drivers, that is N × 200 ms during which diagnostics, TF and the
`set_parameters` reply to config_manager are blocked.

### M6 — per-camera calibration health is not visible in aggregated diagnostics
- The driver's task name is hard-coded as `system/software/jen_sc_camera_driver`
  (`CameraDriverNode.cpp:67`), identical for left and right.
- The aggregator expects `…/jen_sc_camera_driver/left` and `…/right`
  (`shire-sr355/values.yaml:18-19`, `TODO SHIRE-1226`).
- The only signal that tells whether a camera has calibration is therefore not
  aggregated per camera.

### M7 — anyone on the graph can overwrite a driver's calibration
`set_camera_info` is open (for example to the `camera_calibration` GUI). The
manager never reads back or compares, so a foreign write silently diverges from
config_manager until the next push, which may never come (C1/C2).

### L1 — smaller defects
- An empty `service_name` is recorded under the camera's `frame_id`, so it can
  collide with a real service key (`CameraInfoServiceClient.cpp:58-60`).
- A late response from an earlier push can re-insert a failure after a newer
  push has called `resetFailureCount()`.
- `getCameraInfo()` is read at publish time, so a frame captured before a
  calibration update is published with the new calibration.
- `frame_id_pairs` splits on the first `:` (`CalibrationManagerNode.cpp:34`).
  Frame IDs used by the cameras contain `:` (`SC4:PCIE:0`), so a pair whose
  *parent* is a camera frame cannot be expressed.
- Adjacent, TF only: `transformAvailability_` is computed once, right after the
  update and before anything is published (`:169`). `kTransformCheckPeriod` and
  `transformCheckTimer_` are declared but never used, so `tf_pairs_available`
  stays `False` (the `ForwardingDisabled` test asserts exactly that).

### L2 — documentation drift
- `shire-apps/local-dev/README.md:115` still documents `forwarding_enabled`, and
  `.claude/projects/jen_calibration_manager/.claude/skills/project/SKILL.md`
  describes `forwarding_enabled`, `required_transformations` and an
  "on_set_parameters" callback. None of these exist in `master`: the node uses
  `frame_id_pairs` and a post-set callback.
- The chart describes `camera_info_static` as "pushed once at startup", which
  §2.1 shows is not guaranteed.

---

## 4. Scenarios where the workflow is unstable or incorrect

| # | scenario | what happens | result |
|---|---|---|---|
| S1 | Cold boot, every pod starts together | The startup push depends on parameter order (C1). If it fires, it is one 200 ms attempt while the drivers may still be in `initializeFromConfigManager` (≤10 s) | **Camera stays uncalibrated, and every goal is rejected.** The manager's diagnostics show `set_camera_info_failures = 0` (if the send never happened) or a failure entry, but the status level is not raised. Only the driver reports ERROR |
| S2 | Driver becomes ready after the manager (image pull, slow hardware, config_manager late) | `service is not available` is recorded once, with no retry | Same as S1. Recovery only by restarting the manager or re-setting the parameter |
| S3 | Driver container restarts (crash, OOM, `camera_->init` throws, node reboot) | The new process has no calibration (ephemeral file) and the manager does not notice | **Permanently uncalibrated after the first driver restart** |
| S4 | Manager restarts while the drivers are up | The drivers keep their last in-memory calibration, and the re-push depends on C1 ordering | Usually harmless, unless the config changed in the meantime, in which case the drivers keep stale intrinsics |
| S5 | `camera_info_static` updated at runtime while one driver is down | A failure is recorded for that driver and never retried | That driver comes back uncalibrated (S3), while the other has the new values |
| S6 | DDS discovery slower than 200 ms (multi-host, discovery server, loaded node) | `wait_for_service` fails on a freshly created client | False "not available", with C1/C2 consequences |
| S7 | Typo in `service_name`, or the driver's `nodeName`/namespace changes | Same message as S2 | Indistinguishable from a late start (H4) |
| S8 | Intrinsics fail validation (fx ≤ 0, skew, principal point) | Diagnostics show ERROR, but the values are pushed anyway, and the driver accepts them if `k[0] != 0` | **Images are published with invalid calibration** (H1) |
| S9 | Current SR355 config | Camera frames `SC4:PCIE:*` are not in TF; `P` is the identity | **Images cannot be placed in TF, and P-based projection is wrong.** `frame_id_topology` and `intrinsics_validity` report `ok` (H2, H3) |
| S10 | One malformed field (for example `k` with 8 values) in any category | The whole update is dropped, and the parameter value differs from the active data | Old intrinsics stay active, and no diagnostics key shows the rejection (M2) |
| S11 | A camera is removed, or `pairs: []` is set | Ignored by `updateCalibrationData` | The old calibration keeps being pushed (M1) |
| S12 | The same camera appears in both `camera_info` and `camera_info_static` | Two pushes in callback order | Non-deterministic winner (M3) |
| S13 | A driver dies after receiving the request | The future never resolves | No failure and no success, so the state is unknown (C3) |
| S14 | Driver pod hardened (read-only root filesystem / non-root) | The update is applied but the save fails, so `success=false` | The manager reports failures for calibrations that are actually active (M4) |
| S15 | Someone runs `camera_calibration` or calls `set_camera_info` by hand | The driver takes the foreign values | Silent divergence from config_manager (M7) |
| S16 | Calibration changes during an acquisition | Captured with the old calibration, published with the new one | Wrong `camera_info` for that frame (L1) |
| S17 | Goal arrives before the first push | Rejected | **Correct, fail-safe behaviour.** Listed so that it is not mistaken for a bug |

---

## 5. Recommendations

Ordered so that each step removes the largest remaining risk.

1. **Make delivery state-based instead of event-based** (fixes C1, C2, S1-S6).
   Preferred: the manager publishes one `sensor_msgs/CameraInfo` per camera on a
   `transient_local`, reliable topic (for example `/camera/<camera_id>/calibration`),
   and the driver subscribes and applies it via `CameraInfoManager::setCameraInfo`.
   Late joiners and restarted drivers receive the last value automatically, with no
   discovery race and no retry logic.
   If the service must stay, add reconciliation instead: a timer in the manager
   that re-pushes to any service that has not acknowledged the current value
   (per-camera hash), and re-pushes when a service reappears after being absent.
2. **Decouple the startup push from parameter order.** Read `diagnostics.health`
   outside the per-callback parse, or ignore it there, and trigger one full
   publish after the constructor completes (for example with a one-shot timer once
   spinning starts), not only from the post-set callback.
3. **Track per-camera delivery state** (`pending` / `ok @ t, hash` / `failed:
   reason`) and expose each one in diagnostics. Give requests a deadline and drop
   stale ones (`prune_requests_older_than`). Stop clearing every failure on each
   push.
4. **Gate on validation.** Do not push a pair that fails its own checks. Report
   it per camera.
   On the driver side, reject `fx/fy ≤ 0` and a degenerate `P`, and check
   `width/height` against the frame or sensor size. Keep "uncalibrated → reject
   goals" as the fail-safe.
5. **Widen the validators.** Check the camera `frame_id` against TF for
   `camera_info_static` as well, check `P` against `K`, reject duplicate
   `service_name`s within and across lists, and reject an empty `frame_id`.
6. **Key the contract on `camera_id`.** Either derive the target from it, or have
   the driver advertise or subscribe under `/camera/<camera_id>/…` like its other
   interfaces. That leaves one value per camera in the umbrella chart instead of
   three.
7. **Explicit removal semantics** for empty categories. Report parse errors in
   diagnostics, and keep the parameter and the active data consistent: reject the
   parameter in a pre-set or on-set callback instead of accepting it and then
   failing in post-set.
8. **Driver hygiene.** Give each camera its own diagnostic name (SHIRE-1226).
   Either give `CameraInfoManager` an explicit URL on an `emptyDir`, or treat a
   save failure as non-fatal, so that `success` reflects the update.
9. **Tests that would have caught this:**
   - the driver's service appears *after* the manager has pushed;
   - the driver restarts;
   - `initializeFromConfigManager` delivers parameters in different orders (the
     `_impl` template already accepts a mock client);
   - a validation failure blocks the push;
   - an SR355-shaped config fails `frame_id_topology`.

---

## 6. What this review did not verify

- **The deployed calibration-manager image.** It was not compared with `master`,
  because `25ab967` is not in the local clone.
- **The C1 ordering failure was not reproduced live here.** It follows from the
  code (`unordered_map` order + `get_parameter("diagnostics.health")` on a
  declared-but-unset typed parameter, which throws in jazzy). It also matches
  the observation recorded in `shire-apps/local-dev/nudge_camera_info.py`.
- **Dev mode (`without_config_manager: true`).** Whether `declare_parameter` with
  an override fires the post-set callback in jazzy `rclcpp` decides whether
  anything is pushed at all in that mode. I did not check it.
- **Upstream `camera_info_manager` behaviour.** That `isCalibrated()` tests only
  `k[0]` and that `success` reflects the file save is upstream behaviour I did not
  re-read for 5.1.8. The service name and the default URL were confirmed from the
  library inside the driver image.
