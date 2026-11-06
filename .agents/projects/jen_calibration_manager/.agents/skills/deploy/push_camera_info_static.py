#!/usr/bin/env python3
"""Re-set jen_calibration_manager's camera_info_static parameter at runtime,
which makes the node push every pair to its camera driver via SetCameraInfo.

Needed because a value supplied with --params-file is parsed during parameter
declaration and is never pushed (see lr_camera_info_check.sh). Uses the node's
set_parameters service directly: `ros2 param load` asserts on this params file.

  python3 push_camera_info_static.py /params.yaml [--node /jen_calibration_manager]
"""

import argparse
import sys

import rclpy
import yaml
from rcl_interfaces.msg import Parameter, ParameterType, ParameterValue
from rcl_interfaces.srv import SetParameters


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("params_file")
    parser.add_argument("--node", default="/jen_calibration_manager")
    parser.add_argument("--timeout", type=float, default=10.0)
    args = parser.parse_args()

    with open(args.params_file, encoding="utf-8") as handle:
        document = yaml.safe_load(handle)
    section = document.get("/**") or document.get(args.node.lstrip("/")) or document.get(args.node)
    value = section["ros__parameters"]["camera_info_static"]

    rclpy.init()
    node = rclpy.create_node("push_camera_info_static")
    try:
        client = node.create_client(SetParameters, f"{args.node}/set_parameters")
        if not client.wait_for_service(timeout_sec=args.timeout):
            print(f"FAIL: {args.node}/set_parameters not available")
            return 1
        request = SetParameters.Request()
        request.parameters = [Parameter(
            name="camera_info_static",
            value=ParameterValue(type=ParameterType.PARAMETER_STRING, string_value=value))]
        future = client.call_async(request)
        rclpy.spin_until_future_complete(node, future, timeout_sec=args.timeout)
        if not future.done():
            print("FAIL: set_parameters timed out")
            return 1
        result = future.result().results[0]
        print(f"{'OK' if result.successful else 'FAIL'}: camera_info_static set {result.reason}".rstrip())
        return 0 if result.successful else 1
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    sys.exit(main())
