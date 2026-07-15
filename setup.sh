#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

clone_if_missing() {
    local dir="$1" url="$2"
    if [[ -d "$dir/.git" ]]; then
        echo "$dir already present"
    else
        echo "Cloning $url into $dir ..."
        git clone "$url" "$dir"
    fi
}

GZ_PROCEDURAL_WORLDS_DIR="${GZ_PROCEDURAL_WORLDS_DIR:-$PARENT_DIR/gz_procedural_worlds}"
GZ_CUSTOM_MODELS_DIR="${GZ_CUSTOM_MODELS_DIR:-$PARENT_DIR/gz_custom_models}"

clone_if_missing "$GZ_PROCEDURAL_WORLDS_DIR" "https://github.com/mdominmo/gz_procedural_worlds.git"
clone_if_missing "$GZ_CUSTOM_MODELS_DIR" "https://github.com/mdominmo/gz_custom_models.git"

# Chained: gz_procedural_worlds brings in its own dependency
# (px4-sitl-docker-sim) as a sibling of itself - flat, not nested, even
# though the dependency is transitive.
GZ_PROCEDURAL_WORLDS_SETUP="$GZ_PROCEDURAL_WORLDS_DIR/setup.sh"
if [[ -x "$GZ_PROCEDURAL_WORLDS_SETUP" ]]; then
    "$GZ_PROCEDURAL_WORLDS_SETUP"
else
    echo "Warning: $GZ_PROCEDURAL_WORLDS_SETUP not found or not executable - skipping."
fi
