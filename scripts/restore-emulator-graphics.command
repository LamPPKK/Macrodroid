#!/bin/zsh
set -euo pipefail

readonly PROJECT_DIR="${0:A:h:h}"
source "$PROJECT_DIR/scripts/android-environment.sh"
SDK_ROOT="$(tft_resolve_android_sdk_root)"
readonly SDK_ROOT
readonly LIB_DIR="${TFT_EMULATOR_LIB_DIR:-$SDK_ROOT/emulator/lib64}"
readonly ANGLE_DIR="$LIB_DIR/gles_angle"

restore_library() {
    local active="$1"
    local backup="$active.tftmac-original"

    if [[ -L "$active" && -f "$backup" ]]; then
        unlink "$active"
        mv "$backup" "$active"
        print "Restored $active"
    fi
}

restore_library "$LIB_DIR/libgfxstream_backend.dylib"
restore_library "$ANGLE_DIR/libEGL.dylib"
restore_library "$ANGLE_DIR/libGLESv2.dylib"

for dependency in \
    "$ANGLE_DIR/libgallium-26.1.4.dylib" \
    "$ANGLE_DIR/libLLVM-Mesa22.dylib"; do
    if [[ -L "$dependency" ]]; then
        unlink "$dependency"
    fi
done

print "The standard emulator graphics libraries were restored."
