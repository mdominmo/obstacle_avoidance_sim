#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GZ_PROC_DIR="$REPO_ROOT/gz_procedural_worlds"
SIM_DIR="$GZ_PROC_DIR/px4-sitl-docker-sim"
CUSTOM_MODELS_DIR="$REPO_ROOT/gz_custom_models/models"
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
REBUILD=false

# ─── Usage ───────────────────────────────────────────────────────────────────

usage() {
    echo "Usage: $0 --config <yaml> [--seed N] [--model MODEL] [--autostart ID]"
    echo ""
    echo "Options:"
    echo "  --config, -c      World config file (required). E.g.: gz_procedural_worlds/configs/default.yaml"
    echo "  --seed, -s        Random seed override"
    echo "  --model, -m       Drone model name (default: x500_4rangefinders)"
    echo "  --autostart, -a   PX4 SYS_AUTOSTART (default: 4001)"
    echo "  --rebuild          Force rebuild all Docker images"
    echo "  --help, -h        Show this help"
}

# ─── Argument Parsing ────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config|-c)    CONFIG="$2"; shift 2 ;;
        --seed|-s)      SEED="$2"; shift 2 ;;
        --model|-m)     MODEL="$2"; shift 2 ;;
        --autostart|-a) AUTOSTART="$2"; shift 2 ;;
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

if [[ ! -f "$GZ_PROC_DIR/src/gz_procedural_worlds/__init__.py" ]]; then
    echo "Error: gz_procedural_worlds submodule not initialized."
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

if [[ ! -f "$CUSTOM_MODELS_DIR/$MODEL/model.sdf" ]]; then
    echo "Error: model '$MODEL' not found at $CUSTOM_MODELS_DIR/$MODEL/"
    exit 1
fi

# ─── Extract gz_assets ───────────────────────────────────────────────────────

if [[ ! -d "$SIM_DIR/gz_assets" ]]; then
    echo "Extracting gz_assets.zip..."
    (cd "$SIM_DIR" && unzip -o gz_assets.zip)
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
    docker build \
        --build-arg UID="$(id -u)" \
        --build-arg GID="$(id -g)" \
        -t "$SIM_IMAGE" \
        "$SIM_DIR"
fi

if ! docker image inspect "$WORLDGEN_IMAGE" &>/dev/null; then
    echo "Building $WORLDGEN_IMAGE..."
    docker build -t "$WORLDGEN_IMAGE" -f "$GZ_PROC_DIR/Dockerfile.worldgen" "$GZ_PROC_DIR"
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

GEN_ARGS="generate --config /configs/$CONFIG_FILE --output-dir /output --no-sync"
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

# ─── Copy Assets to gz_assets ────────────────────────────────────────────────

echo ""
echo "=== Preparing assets ==="

cp "$WORLD_SDF" "$SIM_DIR/gz_assets/worlds/"
echo "  Copied world: $WORLD_NAME.sdf → gz_assets/worlds/"

cp -r "$CUSTOM_MODELS_DIR/$MODEL" "$SIM_DIR/gz_assets/models/"
echo "  Copied model: $MODEL → gz_assets/models/"

for model_dir in "$GZ_PROC_DIR/models"/*/; do
    if [[ -d "$model_dir" ]]; then
        model_name="$(basename "$model_dir")"
        cp -r "$model_dir" "$SIM_DIR/gz_assets/models/"
        echo "  Copied obstacle model: $model_name → gz_assets/models/"
    fi
done

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

xhost +local:docker

docker run -d --name "$SIM_CONTAINER" \
    --network host \
    --ipc=host \
    --gpus all \
    -e DISPLAY="$DISPLAY" \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e NVIDIA_DRIVER_CAPABILITIES=all \
    -e __NV_PRIME_RENDER_OFFLOAD=1 \
    -e __GLX_VENDOR_LIBRARY_NAME=nvidia \
    -e GZ_IP=127.0.0.1 \
    -e GZ_PARTITION=oa_sim \
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
    -v "$HOME/.Xauthority:/home/dev/.Xauthority:ro" \
    -v "$SIM_DIR/gz_assets/models:/workspace/px4_sitl_docker_sim/gz_assets/models" \
    -v "$SIM_DIR/gz_assets/worlds:/workspace/px4_sitl_docker_sim/gz_assets/worlds" \
    "$SIM_IMAGE" \
    --model "$MODEL" --autostart "$AUTOSTART" --world "$WORLD_NAME"

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
echo "ROS2 topics available:"
echo "  /rangefinder/front"
echo "  /rangefinder/back"
echo "  /rangefinder/left"
echo "  /rangefinder/right"
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
