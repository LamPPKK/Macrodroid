#!/bin/zsh
set -euo pipefail

unsetopt BG_NICE

readonly PROJECT_DIR="${0:A:h}"
readonly EXPERIMENT_PROFILE="$PROJECT_DIR/artifacts/tft-pbe-18.1-5212127-angle-opengl/Android_Codex.DeviceProfiles.performance-max.ini"

export TFT_ANGLE_OPENGL_PROFILE="$EXPERIMENT_PROFILE"
export TFT_ANGLE_OPENGL_PROFILE_SHA256="5ab532b82e2706898d66b4325f880e0ab52982be36e70577a7a6f4aa12d2f8fa"
export TFT_ANGLE_DISABLED_FEATURES="${TFT_ANGLE_DISABLED_FEATURES:-preferSubmitAtFBOBoundary}"
export TFT_ASG_WRITE_STEP_SIZE="${TFT_ASG_WRITE_STEP_SIZE:-16384}"

print "TFT performance-max: 67% 3D scale, reduced effects/LOD work, 16 KiB ASG writes, and no FBO-boundary submit."
print "The full-resolution UI and the stable profile remain unchanged."

exec "$PROJECT_DIR/run-tft-fast-quality.command"
