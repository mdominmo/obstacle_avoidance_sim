#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GZ_PROCEDURAL_WORLDS_DIR="${GZ_PROCEDURAL_WORLDS_DIR:-$REPO_ROOT/../gz_procedural_worlds}"
GZ_CUSTOM_MODELS_DIR="${GZ_CUSTOM_MODELS_DIR:-$REPO_ROOT/../gz_custom_models}"
PX4_SITL_DOCKER_SIM_DIR="${PX4_SITL_DOCKER_SIM_DIR:-$REPO_ROOT/../px4-sitl-docker-sim}"
CUSTOM_MODELS_DIR="$GZ_CUSTOM_MODELS_DIR/models"
OUTPUT_DIR="$REPO_ROOT/output"

SIM_IMAGE="px4_sitl_docker_sim"
WORLDGEN_IMAGE="oa_worldgen"
BRIDGE_IMAGE="oa_bridge"

SIM_CONTAINER="oa_sim"
BRIDGE_CONTAINER="oa_bridge"

# ─── Defaults ────────────────────────────────────────────────────────────────

CONFIG=""
SEED=""
MODEL="x500_4rangefinders"
AUTOSTART="4001"
VEHICLES="1"
REBUILD=false

# ─── Usage ───────────────────────────────────────────────────────────────────

usage() {
    echo "Usage: $0 --config <yaml> [--seed N] [--model MODEL] [--autostart ID] [--vehicles N]"
    echo ""
    echo "Options:"
    echo "  --config, -c      World config file (required). E.g.: gz_procedural_worlds/configs/default.yaml"
    echo "  --seed, -s        Random seed override"
    echo "  --model, -m       Drone model name (default: x500_4rangefinders)"
    echo "  --autostart, -a   PX4 SYS_AUTOSTART (default: 4001)"
    echo "  --vehicles, -n    Number of vehicles to spawn (default: 1)"
    echo "  --rebuild          Force rebuild all Docker images"
    echo "  --help, -h        Show this help"
    echo ""
    echo "NOTE: the rangefinder ROS2 bridge only covers vehicle 1 (GZ_MODEL_INSTANCE"
    echo "is hardcoded to \${MODEL}_1, and /rangefinder/* topic names aren't"
    echo "vehicle-namespaced) - with --vehicles > 1, OAS obstacle avoidance data is"
    echo "only wired up for the first vehicle today."
}

# ─── Argument Parsing ────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config|-c)    CONFIG="$2"; shift 2 ;;
        --seed|-s)      SEED="$2"; shift 2 ;;
        --model|-m)     MODEL="$2"; shift 2 ;;
        --autostart|-a) AUTOSTART="$2"; shift 2 ;;
        --vehicles|-n)  VEHICLES="$2"; shift 2 ;;
        --rebuild)      REBUILD=true; shift ;;
        --help|-h)      usage; exit 0 ;;
        *)              echo "Unknown argument: $1"; usage; exit 1 ;;
    esac
done

if [[ -z "$CONFIG" ]]; then
    echo "Error: --config is required"
    usage
    exit 1
fi

CONFIG_ABSPATH="$(cd "$(dirname "$CONFIG")" && pwd)/$(basename "$CONFIG")"
if [[ ! -f "$CONFIG_ABSPATH" ]]; then
    echo "Error: config file not found: $CONFIG"
    exit 1
fi

# ─── Cleanup Handler ─────────────────────────────────────────────────────────

cleanup() {
    echo ""
    echo "Stopping containers..."
    docker stop "$SIM_CONTAINER" 2>/dev/null || true
    docker stop "$BRIDGE_CONTAINER" 2>/dev/null || true

    echo "--- Simulator logs (last 50 lines) ---"
    docker logs --tail 50 "$SIM_CONTAINER" 2>&1 || true
    echo "--- End simulator logs ---"

    echo "--- Bridge logs (last 30 lines) ---"
    docker logs --tail 30 "$BRIDGE_CONTAINER" 2>&1 || true
    echo "--- End bridge logs ---"

    docker rm "$SIM_CONTAINER" 2>/dev/null || true
    docker rm "$BRIDGE_CONTAINER" 2>/dev/null || true
    xhost -local:docker 2>/dev/null || true
    echo "Done."
}

trap cleanup EXIT INT TERM

# ─── Prerequisites ───────────────────────────────────────────────────────────

echo "=== Checking prerequisites ==="

if ! command -v docker &>/dev/null; then
    echo "Error: docker is not installed"
    exit 1
fi

if ! docker info 2>/dev/null | grep -q "Runtimes.*nvidia\|nvidia-container"; then
    echo "Warning: nvidia-container-toolkit may not be installed. GPU passthrough might fail."
fi

if [[ ! -f "$GZ_PROCEDURAL_WORLDS_DIR/src/gz_procedural_worlds/__init__.py" ]]; then
    echo "Error: gz_procedural_worlds not found at $GZ_PROCEDURAL_WORLDS_DIR."
    echo "Run: ./setup.sh (or set GZ_PROCEDURAL_WORLDS_DIR to an existing checkout)"
    exit 1
fi

if [[ ! -f "$PX4_SITL_DOCKER_SIM_DIR/scripts/run_docker.sh" ]]; then
    echo "Error: px4-sitl-docker-sim not found at $PX4_SITL_DOCKER_SIM_DIR."
    echo "Run: ./setup.sh (or set PX4_SITL_DOCKER_SIM_DIR to an existing checkout)"
    exit 1
fi

if [[ ! -f "$CUSTOM_MODELS_DIR/$MODEL/model.sdf" ]]; then
    echo "Error: model '$MODEL' not found at $CUSTOM_MODELS_DIR/$MODEL/"
    exit 1
fi

# ─── Build Images ────────────────────────────────────────────────────────────

echo ""
echo "=== Building Docker images ==="

if $REBUILD; then
    echo "Forcing rebuild of all images..."
    docker rmi "$SIM_IMAGE" "$WORLDGEN_IMAGE" "$BRIDGE_IMAGE" 2>/dev/null || true
fi

if ! docker image inspect "$SIM_IMAGE" &>/dev/null; then
    echo "Building $SIM_IMAGE (this takes a while on first run)..."
    "$PX4_SITL_DOCKER_SIM_DIR/scripts/build_docker.sh"
fi

if ! docker image inspect "$WORLDGEN_IMAGE" &>/dev/null; then
    echo "Building $WORLDGEN_IMAGE..."
    docker build -t "$WORLDGEN_IMAGE" -f "$GZ_PROCEDURAL_WORLDS_DIR/Dockerfile.worldgen" "$GZ_PROCEDURAL_WORLDS_DIR"
fi

if ! docker image inspect "$BRIDGE_IMAGE" &>/dev/null; then
    echo "Building $BRIDGE_IMAGE..."
    docker build -t "$BRIDGE_IMAGE" -f "$REPO_ROOT/docker/Dockerfile.bridge" "$REPO_ROOT"
fi

# ─── Generate World ──────────────────────────────────────────────────────────

echo ""
echo "=== Generating procedural world ==="

mkdir -p "$OUTPUT_DIR"

CONFIG_DIR="$(dirname "$CONFIG_ABSPATH")"
CONFIG_FILE="$(basename "$CONFIG_ABSPATH")"

GEN_ARGS="generate --config /configs/$CONFIG_FILE --output-dir /output"
[[ -n "$SEED" ]] && GEN_ARGS="$GEN_ARGS --seed $SEED"

docker run --rm \
    -v "$CONFIG_DIR:/configs:ro" \
    -v "$OUTPUT_DIR:/output" \
    "$WORLDGEN_IMAGE" $GEN_ARGS

# ─── Extract World Name ──────────────────────────────────────────────────────

WORLD_NAME=$(python3 -c "
import yaml, sys
with open('$CONFIG_ABSPATH') as f:
    data = yaml.safe_load(f)
print(data.get('world', {}).get('name', 'procedural_world'))
" 2>/dev/null || grep -oP '^\s*name:\s*"\K[^"]+' "$CONFIG_ABSPATH" | head -1)

if [[ -z "$WORLD_NAME" ]]; then
    echo "Error: could not extract world name from config"
    exit 1
fi

echo "World name: $WORLD_NAME"

WORLD_SDF="$OUTPUT_DIR/${WORLD_NAME}.sdf"
if [[ ! -f "$WORLD_SDF" ]]; then
    echo "Error: generated world SDF not found at $WORLD_SDF"
    exit 1
fi

# ─── Render Bridge Config ────────────────────────────────────────────────────

echo ""
echo "=== Rendering bridge config ==="

export WORLD_NAME
export GZ_MODEL_INSTANCE="${MODEL}_1"
envsubst '${WORLD_NAME} ${GZ_MODEL_INSTANCE}' \
    < "$REPO_ROOT/config/bridge_config.yaml.template" \
    > "$OUTPUT_DIR/bridge_config.yaml"

echo "  Bridge config: $OUTPUT_DIR/bridge_config.yaml"

# ─── Start Simulator ─────────────────────────────────────────────────────────

echo ""
echo "=== Starting simulator ==="

export GZ_IP=127.0.0.1
export GZ_PARTITION=oa_sim

"$PX4_SITL_DOCKER_SIM_DIR/scripts/run_docker.sh" \
    --detach --name "$SIM_CONTAINER" \
    --model "$MODEL" --autostart "$AUTOSTART" --world "$WORLD_NAME" --vehicles "$VEHICLES" \
    --extra-assets "$OUTPUT_DIR" \
    --extra-assets "$CUSTOM_MODELS_DIR" \
    --extra-assets "$GZ_PROCEDURAL_WORLDS_DIR/models"

echo "Simulator container started: $SIM_CONTAINER"
echo "Waiting for Gazebo + PX4 to initialize (~25s)..."
sleep 25

# ─── Start Bridge ────────────────────────────────────────────────────────────

echo ""
echo "=== Starting bridge ==="

docker run -d --name "$BRIDGE_CONTAINER" \
    --network host \
    --ipc=host \
    -e GZ_IP=127.0.0.1 \
    -e GZ_PARTITION=oa_sim \
    -v "$OUTPUT_DIR/bridge_config.yaml:/config/bridge_config.yaml:ro" \
    "$BRIDGE_IMAGE"

echo "Bridge container started: $BRIDGE_CONTAINER"
echo ""
echo "=== Simulation running ==="
echo ""
echo "ROS2 topics available (vehicle 1 only):"
echo "  /rangefinder/front"
echo "  /rangefinder/rear"
echo "  /rangefinder/left"
echo "  /rangefinder/right"
if [[ "$VEHICLES" != "1" ]]; then
    echo ""
    echo "NOTE: --vehicles $VEHICLES spawned, but the rangefinder bridge only"
    echo "covers vehicle 1 - vehicles 2..$VEHICLES have no OAS sensor data yet."
fi
echo ""
echo "Press Ctrl+C to stop."

# ─── Monitor ─────────────────────────────────────────────────────────────────

while true; do
    if ! docker ps --format '{{.Names}}' | grep -q "^${SIM_CONTAINER}$"; then
        echo "Simulator container stopped unexpectedly."
        break
    fi
    if ! docker ps --format '{{.Names}}' | grep -q "^${BRIDGE_CONTAINER}$"; then
        echo "Bridge container stopped unexpectedly."
        break
    fi
    sleep 5
done
