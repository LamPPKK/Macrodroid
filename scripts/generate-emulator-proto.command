#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d /Applications/Xcode-26.6.0.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
  else
    export DEVELOPER_DIR="$(xcode-select -p)"
  fi
fi
[[ -d "$DEVELOPER_DIR" ]] || { echo "Authoritative Xcode is missing: $DEVELOPER_DIR" >&2; exit 20; }

PROTO="$ROOT/Vendor/AndroidEmulator/emulator_controller.proto"
[[ -f "$PROTO" ]] || { echo "Vendored EmulatorController proto is missing" >&2; exit 21; }

PROTOC=""
for candidate in /opt/homebrew/bin/protoc /usr/local/bin/protoc; do
  if [[ -x "$candidate" ]]; then PROTOC="$candidate"; break; fi
done
[[ -n "$PROTOC" ]] || { echo "Pinned build cannot generate EmulatorController Swift: protoc is not installed at the standard existing toolchain paths." >&2; exit 22; }

SWIFT_PROTOBUF="$ROOT/.build/native-release/SourcePackages/checkouts/swift-protobuf"
GRPC_PROTOBUF="$ROOT/.build/native-release/SourcePackages/checkouts/grpc-swift-protobuf"
[[ -d "$SWIFT_PROTOBUF" && -d "$GRPC_PROTOBUF" ]] || { echo "Pinned Swift package checkouts from Gate 1 are missing." >&2; exit 23; }

/usr/bin/xcrun swift build --package-path "$SWIFT_PROTOBUF" -c release --product protoc-gen-swift >/dev/null
/usr/bin/xcrun swift build --package-path "$GRPC_PROTOBUF" -c release --product protoc-gen-grpc-swift-2 >/dev/null

SWIFT_PLUGIN="$SWIFT_PROTOBUF/.build/release/protoc-gen-swift"
GRPC_PLUGIN="$GRPC_PROTOBUF/.build/release/protoc-gen-grpc-swift-2"
[[ -x "$SWIFT_PLUGIN" ]] || { echo "Pinned protoc-gen-swift build did not produce an executable." >&2; exit 24; }
[[ -x "$GRPC_PLUGIN" ]] || { echo "Pinned protoc-gen-grpc-swift-2 build did not produce an executable." >&2; exit 25; }

PROTO_INCLUDE=""
for candidate in /opt/homebrew/include /usr/local/include; do
  if [[ -f "$candidate/google/protobuf/empty.proto" ]]; then PROTO_INCLUDE="$candidate"; break; fi
done
[[ -n "$PROTO_INCLUDE" ]] || { echo "google/protobuf/empty.proto is missing from the existing protoc installation." >&2; exit 26; }

OUT="$ROOT/Generated/EmulatorController"
/bin/rm -rf "$OUT"
/bin/mkdir -p "$OUT"

"$PROTOC" \
  -I "$ROOT/Vendor/AndroidEmulator" \
  -I "$PROTO_INCLUDE" \
  --plugin="protoc-gen-swift=$SWIFT_PLUGIN" \
  --plugin="protoc-gen-grpc-swift-2=$GRPC_PLUGIN" \
  --swift_out="$OUT" \
  --grpc-swift-2_out="$OUT" \
  "$PROTO"

[[ -f "$OUT/emulator_controller.pb.swift" ]] || { echo "Swift protobuf output missing" >&2; exit 27; }
[[ -f "$OUT/emulator_controller.grpc.swift" ]] || { echo "Swift gRPC output missing" >&2; exit 28; }

echo "Generated EmulatorController Swift client from vendored Emulator 37.1.11 protocol."
