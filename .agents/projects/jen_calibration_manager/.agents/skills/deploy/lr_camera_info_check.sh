#!/usr/bin/env bash
# Live check: do the left and right jen_sc_camera_driver instances use the
# camera_info that jen_calibration_manager pushes to each of them?
#
# Starts two mock camera drivers named like the SR355 deployment
# (jen_sc_camera_driver_left / _right, camera_id camera_left / camera_right),
# then jen_calibration_manager with params_lr.yaml, and runs lr_check.py.
# With -r it also stops the manager, restarts both drivers on their persisted
# ~/.ros volume, and checks that the calibration is restored without a push.
#
# Drivers start BEFORE the manager on purpose: the manager pushes once at
# startup and never retries, so the reverse order fails by design.
set -euo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly skill_dir
readonly prefix="lrcheck"

driver_image="nexus-hil.group.jenoptik.corp:8082/shire/jen_sc_camera_driver:0.0.1-dev-2-MR-13-9274c24"
# Not jen_calibration_manager:latest: that tag has held a msgs-only build that lacks the node.
manager_image="nexus-hil.group.jenoptik.corp:8082/shire/jen_calibration_manager:0.0.1-dev-38-MR-2-71445d6"
domain_id=57
run_restore=false
keep=false
work_dir=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [-d driver_image] [-m manager_image] [-i ros_domain_id] [-r] [-k] [-h]
  -d  camera driver image      (default: ${driver_image})
  -m  calibration manager image (default: ${manager_image})
  -i  ROS_DOMAIN_ID            (default: ${domain_id})
  -r  also run the restart/restore phase
  -k  keep containers and volumes afterwards (for manual poking)
EOF
}

log() { printf '\n>>> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }

parse_args() {
    while getopts ":d:m:i:rkh" opt; do
        case "${opt}" in
            d) driver_image="${OPTARG}" ;;
            m) manager_image="${OPTARG}" ;;
            i) domain_id="${OPTARG}" ;;
            r) run_restore=true ;;
            k) keep=true ;;
            h) usage; exit 0 ;;
            :) die "option -${OPTARG} needs a value" ;;
            *) usage >&2; exit 2 ;;
        esac
    done
    [[ "${domain_id}" =~ ^[0-9]+$ ]] || die "ROS_DOMAIN_ID must be an integer, got '${domain_id}'"
    for f in params_lr.yaml params_driver.yaml lr_check.py; do
        [[ -f "${skill_dir}/${f}" ]] || die "missing ${skill_dir}/${f}"
    done
    docker image inspect "${driver_image}" >/dev/null 2>&1 || die "driver image not found: ${driver_image}"
    docker image inspect "${manager_image}" >/dev/null 2>&1 || die "manager image not found: ${manager_image}"
}

cleanup() {
    local status=$?
    if [[ "${keep}" == true ]]; then
        log "kept: containers ${prefix}-drv-left ${prefix}-drv-right ${prefix}-jcm; volumes ${prefix}-ros-left ${prefix}-ros-right"
    else
        docker rm -f "${prefix}-drv-left" "${prefix}-drv-right" "${prefix}-jcm" >/dev/null 2>&1 || true
        docker volume rm "${prefix}-ros-left" "${prefix}-ros-right" >/dev/null 2>&1 || true
    fi
    [[ -n "${work_dir}" ]] && rm -rf "${work_dir}"
    exit "${status}"
}

make_test_image() {
    work_dir="$(mktemp -d)"
    mkdir -p "${work_dir}/images"
    docker run --rm --user "$(id -u):$(id -g)" -v "${work_dir}/images:/images" \
        --entrypoint python3 "${driver_image}" \
        -c 'import cv2, numpy as np; cv2.imwrite("/images/frame.bmp", np.full((48, 64), 128, np.uint8))'
}

# start_driver <side>
start_driver() {
    local side="$1"
    docker rm -f "${prefix}-drv-${side}" >/dev/null 2>&1 || true
    docker run -d --name "${prefix}-drv-${side}" \
        --network host --ipc host -e ROS_DOMAIN_ID="${domain_id}" \
        -v "${skill_dir}/params_driver.yaml:/params_driver.yaml:ro" \
        -v "${work_dir}/images:/images:ro" \
        -v "${prefix}-ros-${side}:/root/.ros" \
        --entrypoint bash "${driver_image}" \
        -c "source /ros2_ws/install/setup.bash && exec ros2 run jen_sc_camera_driver jen_sc_camera_driver_mock \
            --ros-args -r __ns:=/ -r __node:=jen_sc_camera_driver_${side} \
            --params-file /params_driver.yaml -p camera_id:=camera_${side}" >/dev/null
}

# wait_for_log <container> <pattern> <timeout_s>
wait_for_log() {
    local container="$1" pattern="$2" timeout="$3" waited=0
    until docker logs "${container}" 2>&1 | grep -q "${pattern}"; do
        if [[ "$(docker inspect -f '{{.State.Running}}' "${container}" 2>/dev/null)" != "true" ]]; then
            docker logs "${container}" 2>&1 | tail -20 >&2
            die "${container} exited before logging '${pattern}'"
        fi
        (( waited >= timeout )) && { docker logs "${container}" 2>&1 | tail -20 >&2; die "timeout waiting for '${pattern}' in ${container}"; }
        sleep 1
        waited=$((waited + 1))
    done
}

start_manager() {
    docker rm -f "${prefix}-jcm" >/dev/null 2>&1 || true
    docker run -d --name "${prefix}-jcm" \
        --network host --ipc host -e ROS_DOMAIN_ID="${domain_id}" \
        -v "${skill_dir}/params_lr.yaml:/params.yaml:ro" \
        --entrypoint bash "${manager_image}" \
        -c 'source /ros2_ws/install/setup.bash && exec ros2 run jen_calibration_manager jen_calibration_manager --ros-args --params-file /params.yaml' >/dev/null
}

push_camera_info_static() {
    docker run --rm --network host --ipc host -e ROS_DOMAIN_ID="${domain_id}" \
        -v "${skill_dir}/push_camera_info_static.py:/push_camera_info_static.py:ro" \
        -v "${skill_dir}/params_lr.yaml:/params.yaml:ro" \
        --entrypoint bash "${driver_image}" \
        -c "source /ros2_ws/install/setup.bash && python3 /push_camera_info_static.py /params.yaml"
}

# run_checker <mode> [extra args...]
run_checker() {
    docker run --rm --network host --ipc host -e ROS_DOMAIN_ID="${domain_id}" \
        -v "${skill_dir}/lr_check.py:/lr_check.py:ro" \
        --entrypoint bash "${driver_image}" \
        -c "source /ros2_ws/install/setup.bash && python3 /lr_check.py $*"
}

show_persisted() {
    local side
    for side in left right; do
        echo "--- /root/.ros/camera_info/camera_${side}.yaml in ${prefix}-drv-${side}"
        docker exec "${prefix}-drv-${side}" cat "/root/.ros/camera_info/camera_${side}.yaml" 2>&1 || true
    done
}

main() {
    parse_args "$@"
    trap cleanup EXIT

    log "resetting leftovers from earlier runs"
    # A persisted calibration from a previous run would make phase 1 pass without any push.
    docker rm -f "${prefix}-drv-left" "${prefix}-drv-right" "${prefix}-jcm" >/dev/null 2>&1 || true
    docker volume rm "${prefix}-ros-left" "${prefix}-ros-right" >/dev/null 2>&1 || true

    log "generating a mock frame"
    make_test_image

    log "starting camera drivers (left, right) on ROS_DOMAIN_ID=${domain_id}"
    start_driver left
    start_driver right
    wait_for_log "${prefix}-drv-left" "Successfully initialized camera driver" 30
    wait_for_log "${prefix}-drv-right" "Successfully initialized camera driver" 30

    log "starting jen_calibration_manager with camera_info_static from --params-file"
    start_manager
    wait_for_log "${prefix}-jcm" "Diagnostic updater is created" 30
    sleep 3

    local status=0
    log "phase 0: did the manager push at startup?"
    # Known manager bug: a --params-file value is parsed while the parameter is still being declared, so
    # has_parameter() is false, pairs stay empty, and nothing is pushed (and nothing is counted as a failure).
    local side startup_pushed=true
    for side in left right; do
        if docker logs "${prefix}-drv-${side}" 2>&1 | grep -q "writing calibration data"; then
            echo "  PASS  ${side}.startup_push_received"
        else
            echo "  FAIL  ${side}.startup_push_received  -- driver never got SetCameraInfo from the manager's startup"
            startup_pushed=false
        fi
    done
    if [[ "${startup_pushed}" == false ]]; then
        status=1
        log "pushing camera_info_static at runtime (set_parameters) so the driver side can still be checked"
        push_camera_info_static
        sleep 2
    fi

    log "phase 1: check both cameras after the push"
    run_checker check || status=1
    log "calibration persisted by CameraInfoManager"
    show_persisted

    if [[ "${run_restore}" == true ]]; then
        log "phase 2: stop manager, restart both drivers on their persisted volumes"
        docker rm -f "${prefix}-jcm" >/dev/null
        start_driver left
        start_driver right
        wait_for_log "${prefix}-drv-left" "Successfully initialized camera driver" 30
        wait_for_log "${prefix}-drv-right" "Successfully initialized camera driver" 30
        run_checker restore || status=1
    fi

    log "overall: $([[ ${status} -eq 0 ]] && echo PASS || echo FAIL)"
    return "${status}"
}

main "$@"
