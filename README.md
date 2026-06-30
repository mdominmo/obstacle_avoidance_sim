# obstacle_avoidance_sim

Simulation environment for testing obstacle avoidance algorithms on drones. It generates procedural worlds in Gazebo Harmonic, simulates a PX4 drone (x500) with onboard sensors, and exposes their readings as ROS2 topics via a bridge — all orchestrated with Docker.

## Components

- **`gz_procedural_worlds/`** (submodule) — Procedural world generator for Gazebo driven by YAML configs: defines the area, spawn zone, obstacles (trees, people, walls, etc.) and lighting, and validates connectivity between the start point and the goals. It also includes the `px4-sitl-docker-sim` submodule, which provides the container with PX4 SITL + Gazebo Harmonic + ROS2.
- **`gz_custom_models/`** (submodule) — Custom SDF models for the simulator. Currently includes an x500 variant with distance sensors; additional sensor configurations (cameras, external IMUs, etc.) are expected to be added as the project evolves.
- **`config/`** — `ros_gz_bridge` config template that maps drone sensor topics from Gazebo into ROS2.
- **`docker/`** — Dockerfile for the bridge container (ROS2 Humble + `ros_gz_bridge`).
- **`scripts/run_simulation.sh`** — Main entrypoint: builds the required Docker images, generates the world, launches the simulator and the bridge, and keeps them running until interrupted.

## Quick start

```bash
git submodule update --init --recursive
./scripts/run_simulation.sh --config gz_procedural_worlds/configs/default.yaml
```

## Requirements

- Docker + NVIDIA Container Toolkit (GPU rendering)
- X11 (graphical simulation interface)
