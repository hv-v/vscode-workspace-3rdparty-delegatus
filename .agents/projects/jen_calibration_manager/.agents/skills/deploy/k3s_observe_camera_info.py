#!/usr/bin/env python3
"""Observe (and optionally prove) the camera_info chain in the k3s cluster.

Default is read-only: it subscribes to /diagnostics and the camera_info topics
and queries the ROS graph - no parameter, service call or goal.

  --expect DOC   compare what each driver holds against a camera_info_static
                 document (the file pushed through config_manager). The
                 persisted YAML is not visible from here, so without --trigger
                 this checks diagnostics only; pass the persisted K yourself
                 (see SKILL.md) or add --trigger.
  --trigger      NOT read-only: send one image request per camera and compare
                 the camera_info published with that image against DOC.

Pipe it into a camera driver pod (it has rclpy + jen_camera_msgs); a document
must be copied in first:

  kubectl -n shire exec -i deploy/shire-jen-sc-camera-driver-left -c jen-sc-camera-driver-left -- \
    bash -c 'cat > /tmp/observe.py' < k3s_observe_camera_info.py
  kubectl -n shire exec -i deploy/shire-jen-sc-camera-driver-left -c jen-sc-camera-driver-left -- \
    bash -c 'cat > /tmp/expected.yaml' < camera_info_static.test.yaml
  kubectl -n shire exec deploy/shire-jen-sc-camera-driver-left -c jen-sc-camera-driver-left -- \
    bash -c 'source /ros2_ws/install/setup.bash && python3 /tmp/observe.py --expect /tmp/expected.yaml --trigger'

Exit code: 0 if every check passed, 1 otherwise.
"""

import argparse
import sys
import time

import rclpy
import yaml
from action_msgs.msg import GoalStatus
from diagnostic_msgs.msg import DiagnosticArray
from rclpy.action import ActionClient
from rclpy.duration import Duration
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CameraInfo

CAMERAS = {"left": "camera_left", "right": "camera_right"}
LEVELS = {0: "OK", 1: "WARN", 2: "ERROR", 3: "STALE"}
TOLERANCE = 1e-6


def level_name(level):
    value = int.from_bytes(level, "little") if isinstance(level, bytes) else int(level)
    return LEVELS.get(value, str(value))


def load_expected(path):
    """Map side -> expected camera_info dict, keyed by the pair's service_name."""
    with open(path, encoding="utf-8") as handle:
        document = yaml.safe_load(handle)
    expected = {}
    for pair in document.get("pairs", []):
        for side in CAMERAS:
            if pair["service_name"] == f"/jen_sc_camera_driver_{side}/set_camera_info":
                expected[side] = pair["camera_info"]
    return expected


class Observer:
    def __init__(self, node):
        self.node = node
        self.diagnostics = {}
        self.infos = {}
        self.failed = False
        node.create_subscription(DiagnosticArray, "/diagnostics", self._on_diagnostics, 50)
        for side, camera_id in CAMERAS.items():
            node.create_subscription(CameraInfo, f"/camera/{camera_id}/camera_info",
                                     lambda m, side=side: self.infos.__setitem__(side, m), qos_profile_sensor_data)

    def _on_diagnostics(self, msg):
        for status in msg.status:
            self.diagnostics[(status.hardware_id, status.name)] = status

    def spin_for(self, seconds, until=lambda: False):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            rclpy.spin_once(self.node, timeout_sec=0.1)
            if until():
                return True
        return False

    def verdict(self, ok, text):
        self.failed |= not ok
        print(f"  {'PASS' if ok else 'FAIL'}  {text}")

    def trigger(self, camera_id, timeout=15.0):
        client = ActionClient(self.node, _camera_image_action(), f"/camera/{camera_id}/trigger_image")
        try:
            if not client.wait_for_server(timeout_sec=timeout):
                return "no action server"
            goal = _camera_image_action().Goal()
            goal.goal.trigger_time = (self.node.get_clock().now() + Duration(seconds=2.0)).to_msg()
            goal.goal.image_id = f"k3s-observe-{camera_id}"
            goal.goal.allowed_deviation.nanosec = 200_000_000
            goal.goal.parameters.exposure_time.nanosec = 1_000_000
            goal.goal.parameters.gain_factor = 1.0
            sent = client.send_goal_async(goal)
            if not self.spin_for(timeout, sent.done):
                return "goal send timed out"
            if not sent.result().accepted:
                return "goal REJECTED"
            result = sent.result().get_result_async()
            self.spin_for(timeout, result.done)
            if not result.done():
                return "result timed out"
            return "succeeded" if result.result().status == GoalStatus.STATUS_SUCCEEDED else f"status={result.result().status}"
        finally:
            client.destroy()


def _camera_image_action():
    from jen_camera_msgs.action import CameraImage  # only needed with --trigger
    return CameraImage


def close(actual, expected):
    return len(actual) == len(expected) and all(abs(a - e) <= TOLERANCE for a, e in zip(actual, expected))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--seconds", type=float, default=12.0, help="passive listening window")
    parser.add_argument("--expect", help="camera_info_static document to compare against")
    parser.add_argument("--trigger", action="store_true", help="NOT read-only: request one image per camera")
    args = parser.parse_args()
    if args.trigger and not args.expect:
        parser.error("--trigger needs --expect")

    expected = load_expected(args.expect) if args.expect else {}

    rclpy.init()
    node = rclpy.create_node("k3s_camera_info_observer")
    observer = Observer(node)
    observer.spin_for(args.seconds)
    services = {name for name, _ in node.get_service_names_and_types()}

    for side, camera_id in CAMERAS.items():
        driver = f"jen_sc_camera_driver_{side}"
        print(f"=== {side}: /{driver} (camera_id={camera_id})")
        observer.verdict(f"/{driver}/set_camera_info" in services, f"service /{driver}/set_camera_info advertised")
        observer.verdict(node.count_publishers(f"/camera/{camera_id}/camera_info") > 0,
                         f"/camera/{camera_id}/camera_info has a publisher")
        status = next((s for (hw, name), s in observer.diagnostics.items()
                       if hw == camera_id and "jen_sc_camera_driver" in name), None)
        observer.verdict(status is not None and level_name(status.level) == "OK",
                         f"driver diagnostics: {'none' if status is None else level_name(status.level) + ' ' + repr(status.message)}")

        if args.trigger:
            observer.infos.pop(side, None)
            goal = observer.trigger(camera_id)
            observer.verdict(goal == "succeeded", f"image request: {goal}")
            observer.spin_for(5.0, lambda: side in observer.infos)

        info = observer.infos.get(side)
        if info is None:
            print("  ----  camera_info on topic: none (published only with an image; use --trigger)")
            if args.trigger:
                observer.verdict(False, "camera_info received with the image")
            continue
        print(f"  ----  camera_info on topic: frame_id={info.header.frame_id!r} "
              f"fx={info.k[0]} cx={info.k[2]} cy={info.k[5]}")
        exp = expected.get(side)
        if exp is not None:
            observer.verdict(close(list(info.k), exp["k"]), f"K matches document (fx={exp['k'][0]})")
            observer.verdict(close(list(info.d), exp.get("d", [])), "D matches document")
            observer.verdict(close(list(info.p), exp["p"]), "P matches document")
            observer.verdict(info.header.frame_id == exp["header"]["frame_id"],
                             f"frame_id matches document ({exp['header']['frame_id']!r})")
            other = expected.get("right" if side == "left" else "left")
            if other is not None and other["k"] != exp["k"]:
                observer.verdict(not close(list(info.k), other["k"]), "not the other camera's K")

    print("=== jen_calibration_manager")
    manager = [s for (_, name), s in observer.diagnostics.items() if "system/software/jen_calibration_manager" in name]
    if not manager:
        observer.verdict(False, "manager diagnostics received")
    for status in manager:
        print(f"  ----  {status.message!r}")
        for kv in status.values:
            print(f"          {kv.key} = {kv.value}")
            if kv.key == "set_camera_info_failures":
                observer.verdict(kv.value == "0", "set_camera_info_failures == 0")

    node.destroy_node()
    rclpy.shutdown()
    sys.exit(1 if observer.failed else 0)


if __name__ == "__main__":
    main()
