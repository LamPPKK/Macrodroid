#!/bin/zsh
set -euo pipefail

readonly PROJECT_DIR="${0:A:h:h}"
readonly MODE="${1:-}"
readonly SDK_ROOT="${TFT_ROOT_SDK:-${TFT_ANDROID_SDK_ROOT:-/Volumes/MAC MINI M4/TFTMAC/Runtime/sdk}}"
readonly ANGLE_DIR="$SDK_ROOT/emulator/lib64/gles_angle"
readonly EGL_LIBRARY="$ANGLE_DIR/libEGL.dylib"
readonly GLES_LIBRARY="$ANGLE_DIR/libGLESv2.dylib"
readonly SWIFTSHADER_ICD="$ANGLE_DIR/vk_swiftshader_icd.json"
readonly BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tftmac-angle-probe.XXXXXX")"
readonly PROBE="$BUILD_DIR/angle-egl-capability-probe"

cleanup() {
    rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

case "$MODE" in
    default|metal|opengl|swiftshader)
        ;;
    *)
        print -u2 "Usage: ${0:t} default|metal|opengl|swiftshader"
        exit 2
        ;;
esac

for required_file in "$EGL_LIBRARY" "$GLES_LIBRARY"; do
    if [[ ! -f "$required_file" ]]; then
        print -u2 "Packaged ANGLE library is absent: $required_file"
        exit 2
    fi
done
if [[ "$MODE" == "swiftshader" && ! -f "$SWIFTSHADER_ICD" ]]; then
    print -u2 "Packaged SwiftShader ICD is absent: $SWIFTSHADER_ICD"
    exit 2
fi

xcrun clang++ \
    -std=c++17 \
    -Wall \
    -Wextra \
    -Werror \
    -O2 \
    "$PROJECT_DIR/artifacts/angle-egl-probe.cpp" \
    -o "$PROBE"

if [[ "$MODE" == "swiftshader" ]]; then
    # This deliberately asks ANGLE for its non-conformant maximum surface.
    # The probe exits nonzero when the advertised ES 3.2 shader stages fail;
    # compute/image/sync/texture-buffer results remain visible in its output.
    env \
        VK_ICD_FILENAMES="$SWIFTSHADER_ICD" \
        ANGLE_FEATURE_OVERRIDES_ENABLED=exposeNonConformantExtensionsAndVersions \
        "$PROBE" "$EGL_LIBRARY" "$GLES_LIBRARY" vulkan
else
    "$PROBE" "$EGL_LIBRARY" "$GLES_LIBRARY" "$MODE"
fi
