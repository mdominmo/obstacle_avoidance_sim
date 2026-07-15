# obstacle_avoidance_sim

Simulation environment for testing obstacle avoidance algorithms on drones. It generates procedural worlds in Gazebo Harmonic, simulates a PX4 drone (x500) with onboard sensors, and exposes their readings as ROS2 topics via a bridge — all orchestrated with Docker.

## Components

- **`gz_procedural_worlds/`** (sibling, fetched by `./setup.sh`) — Procedural world generator for Gazebo driven by YAML configs: defines the area, spawn zone, obstacles (trees, people, walls, etc.) and lighting, and validates connectivity between the start point and the goals. Brings in its own dependency, `px4-sitl-docker-sim` (PX4 SITL + Gazebo Harmonic + ROS2), as a sibling of itself, the same way.
- **`gz_custom_models/`** (sibling, fetched by `./setup.sh`) — Custom SDF models for the simulator. Currently includes an x500 variant with distance sensors; additional sensor configurations (cameras, external IMUs, etc.) are expected to be added as the project evolves.
- **`config/`** — `ros_gz_bridge` config template that maps drone sensor topics from Gazebo into ROS2.
- **`docker/`** — Dockerfile for the bridge container (ROS2 Humble + `ros_gz_bridge`).
- **`scripts/run_simulation.sh`** — Main entrypoint: builds the required Docker images (delegating the base simulator's own build to `px4-sitl-docker-sim/scripts/build_docker.sh`, never rebuilding it), generates the world, launches the simulator and the bridge, and keeps them running until interrupted.

None of these are git submodules of this repo - each is a plain sibling
checkout fetched by `./setup.sh`, so this repo's own `gz_assets`-equivalent
data never gets copied into `px4-sitl-docker-sim`; the simulator is launched
with `--extra-assets` pointing at this repo's own generated world and
models instead.

## Quick start

```bash
./setup.sh
./scripts/run_simulation.sh --config gz_procedural_worlds/configs/default.yaml
```

Set `GZ_PROCEDURAL_WORLDS_DIR`, `GZ_CUSTOM_MODELS_DIR`, or
`PX4_SITL_DOCKER_SIM_DIR` to point `run_simulation.sh` at existing
checkouts instead of the default siblings (e.g. when this repo is used
inside a larger workspace that already provides them).

## Requirements

- Docker + NVIDIA Container Toolkit (GPU rendering)
- X11 (graphical simulation interface)
