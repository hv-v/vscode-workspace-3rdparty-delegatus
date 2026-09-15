#!/usr/bin/env python3
"""Drive a running jen_calibration_manager node over ROS 2.

Runs *inside* a container built from the app image (it needs rclpy plus the
generated jen_calibration_manager_msgs bindings, both of which live in
/ros2_ws/install). Talks to the node over DDS on the host network.

Commands:
  probe                      list the node, its topics and its services
  watch [--seconds N]        capture /tf, /tf_static and /diagnostics
  nudge                      re-set forwarding_enabled to force a /tf republish
  set-transform P C X Y Z    call ~/set_transformation
  smoke                      probe + nudge + watch + set-transform, with verdicts

Every command writes a JSON report to --report (default /out/report.json) when
that directory exists, and always prints a human-readable summary.
"""

import argparse
import json
import os
import sys
import time

import rclpy
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy

from diagnostic_msgs.msg import DiagnosticArray
from geometry_msgs.msg import TransformStamped
from rcl_interfaces.msg import Parameter, ParameterType, ParameterValue
from rcl_interfaces.srv import GetParameters, SetParameters
from tf2_msgs.msg import TFMessage

# The service type only exists once jen_calibration_manager_msgs has been built
# with srv/SetTransformation.srv. Older images predate it; degrade instead of
# crashing so `probe` still works against them.
try:
    from jen_calibration_manager_msgs.srv import SetTransformation
except ImportError:  # pragma: no cover - depends on the image under test
    SetTransformation = None

NODE = "/jen_calibration_manager"

# /tf_static is latched (transient_local). A subscriber that joins after the
# node has already broadcast will see nothing unless it matches that durability.
QOS_STATIC = QoSProfile(
    depth=100,
    reliability=ReliabilityPolicy.RELIABLE,
    durability=DurabilityPolicy.TRANSIENT_LOCAL,
    history=HistoryPolicy.KEEP_LAST,
)
QOS_VOLATILE = QoSProfile(
    depth=100,
    reliability=ReliabilityPolicy.RELIABLE,
    durability=DurabilityPolicy.VOLATILE,
    history=HistoryPolicy.KEEP_LAST,
)


def spin_for(node, seconds):
    end = time.monotonic() + seconds
    while time.monotonic() < end and rclpy.ok():
        rclpy.spin_once(node, timeout_sec=0.05)


def call(node, client, request, timeout=5.0):
    """Call a service and return the response, or None on timeout."""
    if not client.wait_for_service(timeout_sec=timeout):
        return None
    future = client.call_async(request)
    end = time.monotonic() + timeout
    while time.monotonic() < end and rclpy.ok() and not future.done():
        rclpy.spin_once(node, timeout_sec=0.05)
    return future.result() if future.done() else None


def tf_to_dict(t: TransformStamped):
    return {
        "frame_id": t.header.frame_id,
        "child_frame_id": t.child_frame_id,
        "translation": [
            t.transform.translation.x,
            t.transform.translation.y,
            t.transform.translation.z,
        ],
        "rotation": [
            t.transform.rotation.x,
            t.transform.rotation.y,
            t.transform.rotation.z,
            t.transform.rotation.w,
        ],
    }


def diag_to_dict(status):
    level = status.level
    level = int.from_bytes(level, "big") if isinstance(level, bytes) else int(level)
    return {
        "name": status.name,
        "level": level,
        "message": status.message,
        "values": {kv.key: kv.value for kv in status.values},
    }


def subscribe_all(node, captured):
    """Attach the three observation subscriptions used by watch and smoke."""
    node.create_subscription(
        TFMessage, "/tf",
        lambda m: captured["tf"].extend(tf_to_dict(t) for t in m.transforms),
        QOS_VOLATILE)
    node.create_subscription(
        TFMessage, "/tf_static",
        lambda m: captured["tf_static"].extend(tf_to_dict(t) for t in m.transforms),
        QOS_STATIC)
    node.create_subscription(
        DiagnosticArray, "/diagnostics",
        lambda m: captured["diagnostics"].extend(diag_to_dict(s) for s in m.status),
        QOS_VOLATILE)


def wait_for_node(node, timeout=20.0):
    """Block until the calibration manager shows up in the graph."""
    end = time.monotonic() + timeout
    while time.monotonic() < end and rclpy.ok():
        for name, _ns in node.get_node_names_and_namespaces():
            if name == NODE.lstrip("/"):
                return True
        spin_for(node, 0.2)
    return False


def do_probe(node):
    """Snapshot the running graph."""
    spin_for(node, 2.0)
    nodes = sorted(
        ns.rstrip("/") + "/" + n for n, ns in node.get_node_names_and_namespaces()
    )
    topics = sorted(t for t, _ in node.get_topic_names_and_types())
    services = sorted(s for s, _ in node.get_service_names_and_types())
    return {
        "nodes": nodes,
        "topics": topics,
        "services": services,
        "node_present": any(n.endswith("jen_calibration_manager") for n in nodes),
        "has_set_transformation": any(
            s.endswith("/set_transformation") for s in services
        ),
        "publishes_tf": "/tf" in topics,
        "publishes_tf_static": "/tf_static" in topics,
    }


def do_nudge(node):
    """Re-set the `tf` parameter to its own current value to force a republish.

    /tf is volatile and only broadcast when calibration data changes, so a
    driver that attached after startup would otherwise never see a message.
    `tf` is in the node's watched set, so setting it re-runs
    onConfigurationReceived -> buildCalibrationMessages -> publishCalibrationData.
    """
    getter = node.create_client(GetParameters, f"{NODE}/get_parameters")
    current = call(node, getter, GetParameters.Request(names=["tf"]))
    if current is None or not current.values:
        return {"ok": False, "reason": "could not read the current tf parameter"}
    value = current.values[0]
    if value.type != ParameterType.PARAMETER_STRING:
        return {"ok": False,
                "reason": f"tf is not a string parameter (type {value.type}) - this build "
                          "does not expose calibration data as parameters"}

    setter = node.create_client(SetParameters, f"{NODE}/set_parameters")
    param = Parameter(
        name="tf",
        value=ParameterValue(type=ParameterType.PARAMETER_STRING,
                             string_value=value.string_value),
    )
    resp = call(node, setter, SetParameters.Request(parameters=[param]))
    if resp is None:
        return {"ok": False, "reason": "set_parameters call timed out"}
    results = [{"successful": r.successful, "reason": r.reason} for r in resp.results]
    return {"ok": all(r["successful"] for r in results), "results": results,
            "tf_len": len(value.string_value)}


def do_watch(node, seconds):
    """Capture whatever the node broadcasts over the window."""
    captured = {"tf": [], "tf_static": [], "diagnostics": []}
    subscribe_all(node, captured)
    spin_for(node, seconds)
    return captured


def do_set_transform(node, parent, child, x, y, z):
    if SetTransformation is None:
        return {"ok": False,
                "reason": "jen_calibration_manager_msgs.srv.SetTransformation not in this image"}
    client = node.create_client(SetTransformation, f"{NODE}/set_transformation")
    req = SetTransformation.Request()
    req.transform.header.frame_id = parent
    req.transform.child_frame_id = child
    req.transform.transform.translation.x = float(x)
    req.transform.transform.translation.y = float(y)
    req.transform.transform.translation.z = float(z)
    req.transform.transform.rotation.w = 1.0
    resp = call(node, client, req, timeout=10.0)
    if resp is None:
        return {"ok": False, "reason": "set_transformation call timed out or not offered"}
    # success=False is a legitimate outcome when config_manager is absent - the
    # node is meant to answer, not hang.
    return {"ok": True, "success": resp.success, "message": resp.message}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("command",
                    choices=["probe", "watch", "nudge", "set-transform", "smoke"])
    ap.add_argument("args", nargs="*")
    ap.add_argument("--seconds", type=float, default=6.0)
    ap.add_argument("--report", default="/out/report.json")
    opts = ap.parse_args()

    rclpy.init()
    node = rclpy.create_node("jcm_driver")
    report = {"command": opts.command}
    exit_code = 0

    try:
        if not wait_for_node(node):
            print(f"FAIL: {NODE} never appeared in the ROS graph", file=sys.stderr)
            report["error"] = "node not discovered"
            exit_code = 1
        elif opts.command == "probe":
            report["probe"] = do_probe(node)
        elif opts.command == "nudge":
            report["nudge"] = do_nudge(node)
        elif opts.command == "watch":
            report["watch"] = do_watch(node, opts.seconds)
        elif opts.command == "set-transform":
            if len(opts.args) != 5:
                ap.error("set-transform needs PARENT CHILD X Y Z")
            report["set_transform"] = do_set_transform(node, *opts.args)
        elif opts.command == "smoke":
            probe = do_probe(node)
            report["probe"] = probe

            # Subscribe first, then nudge, so the volatile /tf broadcast lands
            # in a subscriber that already exists.
            captured = {"tf": [], "tf_static": [], "diagnostics": []}
            subscribe_all(node, captured)
            spin_for(node, 1.0)

            report["nudge"] = do_nudge(node)
            spin_for(node, opts.seconds)
            report["watch"] = captured

            checks = {
                "node_present": probe["node_present"],
                "tf_received": len(captured["tf"]) > 0,
                "tf_static_received": len(captured["tf_static"]) > 0,
                "diagnostics_received": len(captured["diagnostics"]) > 0,
            }

            # Only assert on set_transformation if this build actually offers it.
            if probe["has_set_transformation"]:
                report["set_transform"] = do_set_transform(
                    node, "base_link", "driver_probe_link", 9.0, 8.0, 7.0)
                checks["set_transformation_answered"] = report["set_transform"].get("ok", False)
            else:
                report["set_transform"] = {
                    "skipped": "node does not offer ~/set_transformation in this build"}

            report["checks"] = checks
            exit_code = 0 if all(checks.values()) else 1
    finally:
        node.destroy_node()
        rclpy.shutdown()

    print(json.dumps(report, indent=2))
    out_dir = os.path.dirname(opts.report)
    if out_dir and os.path.isdir(out_dir):
        with open(opts.report, "w") as fh:
            json.dump(report, fh, indent=2)
        print(f"\nreport written to {opts.report}", file=sys.stderr)

    if "checks" in report:
        print("\n=== VERDICT ===", file=sys.stderr)
        for name, ok in report["checks"].items():
            print(f"  {'PASS' if ok else 'FAIL'}  {name}", file=sys.stderr)

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
