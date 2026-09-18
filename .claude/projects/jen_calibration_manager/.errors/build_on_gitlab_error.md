
[2026-09-07T18:35:16.478Z] #16 86.21 Preparing to unpack .../ros-jazzy-diagnostic-updater_4.2.7-1noble.20260615.135857_amd64.deb ...

[2026-09-07T18:35:16.478Z] #16 86.21 Unpacking ros-jazzy-diagnostic-updater (4.2.7-1noble.20260615.135857) ...

[2026-09-07T18:35:16.478Z] #16 86.30 Setting up ros-jazzy-diagnostic-updater (4.2.7-1noble.20260615.135857) ...

[2026-09-07T18:35:16.478Z] #16 86.43 executing command [apt-get install -y ros-jazzy-ament-cmake-clang-format]

[2026-09-07T18:35:16.478Z] #16 86.43 executing command [apt-get install -y ros-jazzy-diagnostic-updater]

[2026-09-07T18:35:16.478Z] #16 86.43 #All required rosdeps installed successfully

[2026-09-07T18:35:17.058Z] #16 DONE 86.7s

[2026-09-07T18:35:17.058Z] 

[2026-09-07T18:35:17.058Z] #17 [builder 12/14] RUN  rosdep keys -t exec --from-path src --ignore-src |      xargs rosdep resolve | grep -v '^#' > exec-rosdeps.txt

[2026-09-07T18:35:17.322Z] #17 0.351 /usr/bin/rosdep:6: DeprecationWarning: pkg_resources is deprecated as an API. See https://setuptools.pypa.io/en/latest/pkg_resources.html

[2026-09-07T18:35:17.322Z] #17 0.351   from pkg_resources import load_entry_point

[2026-09-07T18:35:17.895Z] #17 1.042 /usr/bin/rosdep:6: DeprecationWarning: pkg_resources is deprecated as an API. See https://setuptools.pypa.io/en/latest/pkg_resources.html

[2026-09-07T18:35:17.895Z] #17 1.042   from pkg_resources import load_entry_point

[2026-09-07T18:35:18.156Z] #17 1.372 ERROR: no rosdep rule for 'jen_scene_msgs'

[2026-09-07T18:35:18.421Z] #17 DONE 1.6s

[2026-09-07T18:35:18.686Z] 

[2026-09-07T18:35:18.686Z] #18 [builder 13/14] RUN git init /ros2_ws || true

[2026-09-07T18:35:18.686Z] #18 0.226 hint: Using 'master' as the name for the initial branch. This default branch name

[2026-09-07T18:35:18.686Z] #18 0.226 hint: is subject to change. To configure the initial branch name to use in all

[2026-09-07T18:35:18.686Z] #18 0.226 hint: of your new repositories, which will suppress this warning, call:

[2026-09-07T18:35:18.686Z] #18 0.226 hint: 

[2026-09-07T18:35:18.686Z] #18 0.226 hint: 	git config --global init.defaultBranch <name>

[2026-09-07T18:35:18.686Z] #18 0.226 hint: 

[2026-09-07T18:35:18.686Z] #18 0.226 hint: Names commonly chosen instead of 'master' are 'main', 'trunk' and

[2026-09-07T18:35:18.686Z] #18 0.226 hint: 'development'. The just-created branch can be renamed via this command:

[2026-09-07T18:35:18.686Z] #18 0.226 hint: 

[2026-09-07T18:35:18.686Z] #18 0.226 hint: 	git branch -m <name>

[2026-09-07T18:35:18.949Z] #18 0.227 Initialized empty Git repository in /ros2_ws/.git/

[2026-09-07T18:35:18.949Z] #18 DONE 0.4s

[2026-09-07T18:35:18.949Z] 

[2026-09-07T18:35:18.949Z] #19 [builder 14/14] RUN ./build.sh

[2026-09-07T18:35:19.897Z] #19 0.767 Starting >>> jen_logging

[2026-09-07T18:35:19.897Z] #19 0.777 Starting >>> jen_config_manager_interface

[2026-09-07T18:35:19.897Z] #19 0.781 Starting >>> jen_parameter_msgs

[2026-09-07T18:35:19.897Z] #19 0.786 Starting >>> jen_calibration_manager_msgs

[2026-09-07T18:35:21.287Z] #19 2.077 --- stderr: jen_parameter_msgs

[2026-09-07T18:35:21.287Z] #19 2.077 CMake Error at CMakeLists.txt:10 (find_package):

[2026-09-07T18:35:21.287Z] #19 2.077   By not providing "Findjen_scene_msgs.cmake" in CMAKE_MODULE_PATH this

[2026-09-07T18:35:21.287Z] #19 2.077   project has asked CMake to find a package configuration file provided by

[2026-09-07T18:35:21.287Z] #19 2.077   "jen_scene_msgs", but CMake did not find one.

[2026-09-07T18:35:21.287Z] #19 2.077 

[2026-09-07T18:35:21.287Z] #19 2.077   Could not find a package configuration file provided by "jen_scene_msgs"

[2026-09-07T18:35:21.287Z] #19 2.077   with any of the following names:

[2026-09-07T18:35:21.287Z] #19 2.077 

[2026-09-07T18:35:21.287Z] #19 2.077     jen_scene_msgsConfig.cmake

[2026-09-07T18:35:21.287Z] #19 2.077     jen_scene_msgs-config.cmake

[2026-09-07T18:35:21.287Z] #19 2.077 

[2026-09-07T18:35:21.287Z] #19 2.077   Add the installation prefix of "jen_scene_msgs" to CMAKE_PREFIX_PATH or set

[2026-09-07T18:35:21.287Z] #19 2.077   "jen_scene_msgs_DIR" to a directory containing one of the above files.  If

[2026-09-07T18:35:21.287Z] #19 2.077   "jen_scene_msgs" provides a separate development package or SDK, be sure it

[2026-09-07T18:35:21.287Z] #19 2.077   has been installed.

[2026-09-07T18:35:21.287Z] #19 2.077 

[2026-09-07T18:35:21.287Z] #19 2.077 

[2026-09-07T18:35:21.287Z] #19 2.077 ---

[2026-09-07T18:35:21.287Z] #19 2.077 Failed   <<< jen_parameter_msgs [1.30s, exited with code 1]

[2026-09-07T18:35:21.287Z] #19 2.496 Aborted  <<< jen_logging [1.73s]

[2026-09-07T18:35:24.698Z] #19 5.182 Aborted  <<< jen_config_manager_interface [4.40s]

[2026-09-07T18:35:24.698Z] #19 5.617 Aborted  <<< jen_calibration_manager_msgs [4.83s]

[2026-09-07T18:35:24.698Z] #19 5.648 

[2026-09-07T18:35:24.698Z] #19 5.648 Summary: 0 packages finished [5.09s]

[2026-09-07T18:35:24.698Z] #19 5.648   1 package failed: jen_parameter_msgs

[2026-09-07T18:35:24.698Z] #19 5.648   3 packages aborted: jen_calibration_manager_msgs jen_config_manager_interface jen_logging

[2026-09-07T18:35:24.698Z] #19 5.648   1 package had stderr output: jen_parameter_msgs

[2026-09-07T18:35:24.698Z] #19 5.648   3 packages not processed

[2026-09-07T18:35:24.698Z] #19 ERROR: process "/bin/sh -c ./build.sh" did not complete successfully: exit code: 1

[2026-09-07T18:35:24.964Z] ------