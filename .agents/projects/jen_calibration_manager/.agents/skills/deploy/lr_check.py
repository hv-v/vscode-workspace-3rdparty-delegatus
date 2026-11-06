#!/usr/bin/env python3
"""Verify that the left and right jen_sc_camera_driver instances use the
camera_info that jen_calibration_manager pushed to each of them.

Run inside a container built from the camera driver image (it has rclpy,
jen_camera_msgs and sensor_msgs). lr_camera_info_check.sh does that for you.

  python3 lr_check.py check     # after the manager has pushed: full check
  python3 lr_check.py restore   # driver restarted, manager NOT running:
                                # calibration must come back from the
                                # persisted YAML (frame_id is known to be lost)

For every side it proves the value flowed through the driver, not merely that a
service call returned:
  1. the driver's ~/set_camera_info service exists under the expected name
  2. the driver's own /diagnostics reports "Calibration loaded"
  3. a real image request is accepted (handleGoal rejects when uncalibrated)
  4. the camera_info published with that image carries this side's intrinsics
     and frame_id, and not the other side's
Exit code is 0 only if every check passes.
"""

import argparse
import sys
import time

import rclpy
from action_msgs.msg import GoalStatus
from diagnostic_msgs.msg import DiagnosticArray, DiagnosticStatus
from rclpy.action import ActionClient
from rclpy.duration import Duration
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CameraInfo, Image

from jen_camera_msgs.action import CameraImage

# Must match params_lr.yaml.
EXPECTED = {
    "left": {
        "node": "jen_sc_camera_driver_left",
        "camera_id": "camera_left",
        "frame_id": "camera_left_optical",
        "width": 5328,
        "height": 3040,
        "distortion_model": "plumb_bob",
        "d": [-0.047692859, -0.309408765, 0.0, 0.0, 4.951333848],
        "k": [9218.784, 0.0, 2679.771, 0.0, 9218.784, 1551.636, 0.0, 0.0, 1.0],
        "p": [9218.784, 0.0, 2679.771, 0.0, 0.0, 9218.784, 1551.636, 0.0, 0.0, 0.0, 1.0, 0.0],
    },
    "right": {
        "node": "jen_sc_camera_driver_right",
        "camera_id": "camera_right",
        "frame_id": "camera_right_optical",
        "width": 5328,
        "height": 3040,
        "distortion_model": "plumb_bob",
        "d": [-0.0512, -0.2873, 0.0, 0.0, 4.702],
        "k": [9105.5, 0.0, 2650.25, 0.0, 9105.5, 1530.75, 0.0, 0.0, 1.0],
        "p": [9105.5, 0.0, 2650.25, -910.55, 0.0, 9105.5, 1530.75, 0.0, 0.0, 0.0, 1.0, 0.0],
    },
}

TOLERANCE = 1e-6


class Report:
    def __init__(self):
        self.rows = []

    def add(self, verdict, name, detail=""):
        self.rows.append((verdict, name, detail))
        print(f"  {verdict:<4}  {name}" + (f"  -- {detail}" if detail else ""), flush=True)

    def ok(self):
        return all(verdict != "FAIL" for verdict, _, _ in self.rows)


def close(actual, expected):
    return len(actual) == len(expected) and all(abs(a - e) <= TOLERANCE for a, e in zip(actual, expected))


class Checker(Node):
    def __init__(self):
        super().__init__("lr_camera_info_checker")
        self.diagnostics = {}
        self.create_subscription(DiagnosticArray, "/diagnostics", self._on_diagnostics, 50)

    def _on_diagnostics(self, msg):
        for status in msg.status:
            self.diagnostics[(status.hardware_id, status.name)] = status

    def spin_until(self, predicate, timeout):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            rclpy.spin_once(self, timeout_sec=0.1)
            if predicate():
                return True
        return False

    def service_present(self, name, timeout):
        return self.spin_until(lambda: any(n == name for n, _ in self.get_service_names_and_types()), timeout)

    def driver_status(self, camera_id):
        for (hardware_id, name), status in self.diagnostics.items():
            if hardware_id == camera_id and "jen_sc_camera_driver" in name:
                return status
        return None

    def manager_failures(self):
        for (_, name), status in self.diagnostics.items():
            if "jen_calibration_manager" in name:
                for kv in status.values:
                    if kv.key == "set_camera_info_failures":
                        return kv.value
        return None

    def trigger_and_capture(self, camera_id, timeout):
        """Send one image goal and return (goal_status, camera_info, image)."""
        captured = {}
        info_sub = self.create_subscription(
            CameraInfo, f"/camera/{camera_id}/camera_info",
            lambda m: captured.setdefault("info", m), qos_profile_sensor_data)
        image_sub = self.create_subscription(
            Image, f"/camera/{camera_id}/image_raw",
            lambda m: captured.setdefault("image", m), qos_profile_sensor_data)
        client = ActionClient(self, CameraImage, f"/camera/{camera_id}/trigger_image")
        try:
            if not client.wait_for_server(timeout_sec=timeout):
                return "no action server", None, None
            # Give the subscriptions a moment to match before anything is published.
            self.spin_until(lambda: False, 1.0)

            goal = CameraImage.Goal()
            trigger = self.get_clock().now() + Duration(seconds=2.0)
            goal.goal.trigger_time = trigger.to_msg()
            goal.goal.image_id = f"lr-check-{camera_id}"
            goal.goal.allowed_deviation.nanosec = 200_000_000
            goal.goal.parameters.exposure_time.nanosec = 1_000_000
            goal.goal.parameters.gain_factor = 1.0

            send_future = client.send_goal_async(goal)
            if not self.spin_until(send_future.done, timeout):
                return "goal send timed out", None, None
            handle = send_future.result()
            if not handle.accepted:
                return "goal REJECTED", None, None

            result_future = handle.get_result_async()
            self.spin_until(lambda: result_future.done() and "info" in captured, timeout)
            status = result_future.result().status if result_future.done() else None
            status_text = {GoalStatus.STATUS_SUCCEEDED: "succeeded",
                           GoalStatus.STATUS_ABORTED: "aborted",
                           GoalStatus.STATUS_CANCELED: "canceled"}.get(status, f"status={status}")
            return status_text, captured.get("info"), captured.get("image")
        finally:
            client.destroy()
            self.destroy_subscription(info_sub)
            self.destroy_subscription(image_sub)


def check_side(checker, report, side, mode, timeout):
    exp = EXPECTED[side]
    other = EXPECTED["right" if side == "left" else "left"]
    print(f"\n=== {side}: /{exp['node']} (camera_id={exp['camera_id']}) ===", flush=True)

    service = f"/{exp['node']}/set_camera_info"
    report.add("PASS" if checker.service_present(service, timeout) else "FAIL",
               f"{side}.service_present", service)

    checker.spin_until(lambda: checker.driver_status(exp["camera_id"]) is not None, timeout)
    status = checker.driver_status(exp["camera_id"])
    if status is None:
        report.add("FAIL", f"{side}.diagnostics_calibrated", "no driver diagnostics received")
    else:
        calibrated = status.level == DiagnosticStatus.OK
        report.add("PASS" if calibrated else "FAIL", f"{side}.diagnostics_calibrated", status.message)

    goal_status, info, image = checker.trigger_and_capture(exp["camera_id"], timeout)
    report.add("PASS" if goal_status == "succeeded" else "FAIL", f"{side}.image_request", goal_status)
    if info is None:
        report.add("FAIL", f"{side}.camera_info_published", "no camera_info received with the image")
        return
    report.add("PASS", f"{side}.camera_info_published")

    k, d, p = list(info.k), list(info.d), list(info.p)
    intrinsics_ok = (close(k, exp["k"]) and close(d, exp["d"]) and close(p, exp["p"])
                     and info.width == exp["width"] and info.height == exp["height"]
                     and info.distortion_model == exp["distortion_model"])
    report.add("PASS" if intrinsics_ok else "FAIL", f"{side}.intrinsics_match",
               f"fx={k[0]} cx={k[2]} d0={d[0] if d else None} p3={p[3]}")

    swapped = close(k, other["k"])
    report.add("FAIL" if swapped else "PASS", f"{side}.not_other_sides_intrinsics",
               "received the OTHER camera's K" if swapped else "")

    if mode == "check":
        report.add("PASS" if info.header.frame_id == exp["frame_id"] else "FAIL",
                   f"{side}.frame_id_match", repr(info.header.frame_id))
    else:
        # Known gap: camera_calibration_parsers does not persist header.frame_id.
        restored = info.header.frame_id == exp["frame_id"]
        report.add("PASS" if restored else "WARN", f"{side}.frame_id_after_restore",
                   repr(info.header.frame_id) + ("" if restored else " (not persisted by CameraInfoManager)"))

    if image is not None:
        report.add("PASS" if image.header.frame_id == info.header.frame_id else "FAIL",
                   f"{side}.image_frame_id_consistent", repr(image.header.frame_id))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mode", choices=["check", "restore"])
    parser.add_argument("--sides", nargs="+", choices=["left", "right"], default=["left", "right"])
    parser.add_argument("--timeout", type=float, default=15.0)
    args = parser.parse_args()

    rclpy.init()
    checker = Checker()
    report = Report()
    try:
        for side in args.sides:
            check_side(checker, report, side, args.mode, args.timeout)

        if args.mode == "check":
            print("\n=== jen_calibration_manager ===", flush=True)
            checker.spin_until(lambda: checker.manager_failures() is not None, args.timeout)
            failures = checker.manager_failures()
            report.add("PASS" if failures == "0" else "FAIL", "manager.set_camera_info_failures", repr(failures))
    finally:
        checker.destroy_node()
        rclpy.shutdown()

    print("\n=== VERDICT ===")
    for verdict, name, _ in report.rows:
        print(f"  {verdict:<4}  {name}")
    sys.exit(0 if report.ok() else 1)


if __name__ == "__main__":
    main()
