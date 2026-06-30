#!/bin/bash
set -e

source /opt/ros/humble/setup.bash

echo "Waiting for Gazebo transport to initialize..."
sleep 10

echo "Starting ros_gz_bridge with config: /config/bridge_config.yaml"
exec ros2 run ros_gz_bridge parameter_bridge \
    --ros-args -p config_file:=/config/bridge_config.yaml
