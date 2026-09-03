#!/bin/zsh
set -euo pipefail

readonly PROJECT_DIR="${0:A:h:h}"
readonly SOURCE_DIR="$PROJECT_DIR/artifacts/android-egl-capability-probe"
readonly OUTPUT="${1:-$PROJECT_DIR/runtime/android-egl-capability-probe}"
readonly GO_COMMAND="${TFT_GO_COMMAND:-go1.24.3}"
readonly BUILD_CACHE="$(mktemp -d -t tftmac-android-egl-go-cache)"

cleanup() {
    rm -rf "$BUILD_CACHE"
}
trap cleanup EXIT

if ! command -v "$GO_COMMAND" >/dev/null 2>&1; then
    print -u2 "The project Go compiler is unavailable: $GO_COMMAND"
    exit 2
fi

mkdir -p "${OUTPUT:h}"
cd "$SOURCE_DIR"
env \
    GOCACHE="$BUILD_CACHE" \
    GO111MODULE=off \
    GOOS=android \
    GOARCH=arm64 \
    CGO_ENABLED=0 \
    "$GO_COMMAND" build \
        -trimpath \
        -o "$OUTPUT" \
        .
print "$OUTPUT"
