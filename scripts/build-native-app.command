#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
ICON_SOURCE="${ROOT}/tftmac/Assets/TFTMAC-Official-Icon.png"
ICON_SOURCE_SHA256="d6ba9ceb76c4b1e44e87f059f775a0ed629f9bea29b0dd73245853d7dca3a016"
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d /Applications/Xcode-26.6.0.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
  else
    export DEVELOPER_DIR="$(xcode-select -p)"
  fi
fi
DERIVED="${ROOT}/.build/native-release"
APP="${DERIVED}/Build/Products/Release/TFTMAC.app"
DIST="${ROOT}/dist/TFTMAC.app"
ICON_WORK="$(mktemp -d /private/tmp/tftmac-native-icon.XXXXXX)"
SIGNING_IDENTITY_NAME="${TFTMAC_CODE_SIGN_IDENTITY_NAME:-TFTMAC Local Code Signing}"
SIGNING_IDENTITY_HASH="$(/usr/bin/security find-identity -v -p codesigning \
  | /usr/bin/awk -v name="${SIGNING_IDENTITY_NAME}" 'index($0, "\"" name "\"") { print $2; exit }')"

[[ -n "${SIGNING_IDENTITY_HASH}" ]] || {
  print -u2 "TFTMAC requires the stable '${SIGNING_IDENTITY_NAME}' identity. Run scripts/ensure-local-signing-identity.command once."
  exit 1
}
[[ -s "${ICON_SOURCE}" ]] || {
  print -u2 "The official TFTMAC icon source is missing: ${ICON_SOURCE}"
  exit 1
}
[[ "$(/usr/bin/shasum -a 256 "${ICON_SOURCE}" | /usr/bin/awk '{print $1}')" == "${ICON_SOURCE_SHA256}" ]] || {
  print -u2 "The official TFTMAC icon source failed its SHA-256 receipt."
  exit 1
}

cleanup() {
  /bin/rm -rf "${ICON_WORK}"
}
trap cleanup EXIT

/usr/bin/xcodebuild \
  -quiet \
  -project "${ROOT}/TFTMAC.xcodeproj" \
  -scheme TFTMAC \
  -configuration Release \
  -derivedDataPath "${DERIVED}" \
  CODE_SIGNING_ALLOWED=NO \
  build

[[ -d "${APP}" ]] || { echo "Native build did not produce ${APP}" >&2; exit 1; }
/bin/rm -rf "${DIST}"
/bin/mkdir -p "${ROOT}/dist"
/usr/bin/ditto "${APP}" "${DIST}"

# The Info.plist declares TFTMAC.icns. Downsample the official generated
# 1:1 master and embed every required Mac representation before signing.
/usr/bin/sips -z 1024 1024 "${ICON_SOURCE}" --out "${ICON_WORK}/icon_1024x1024.png" >/dev/null
/bin/mkdir -p "${ICON_WORK}/TFTMAC.iconset" "${DIST}/Contents/Resources"
for specification in \
  '16 icon_16x16.png' \
  '32 icon_16x16@2x.png' \
  '32 icon_32x32.png' \
  '64 icon_32x32@2x.png' \
  '128 icon_128x128.png' \
  '256 icon_128x128@2x.png' \
  '256 icon_256x256.png' \
  '512 icon_256x256@2x.png' \
  '512 icon_512x512.png' \
  '1024 icon_512x512@2x.png'; do
  pixels="${specification%% *}"
  filename="${specification#* }"
  /usr/bin/sips -z "${pixels}" "${pixels}" "${ICON_WORK}/icon_1024x1024.png" \
    --out "${ICON_WORK}/TFTMAC.iconset/${filename}" >/dev/null
done
/usr/bin/iconutil -c icns "${ICON_WORK}/TFTMAC.iconset" -o "${DIST}/Contents/Resources/TFTMAC.icns"
/bin/cp "${ICON_WORK}/icon_1024x1024.png" "${DIST}/Contents/Resources/TFTMAC-1024.png"

# Perfetto v58.2 mac-arm64 is pinned by the official manifest SHA-256. Raw
# combat traces are normalized locally with this exact executable before the
# app records any causal trace conclusion.
TRACE_PROCESSOR="$(/bin/zsh "${ROOT}/scripts/install-trace-processor.command")"
/bin/cp "${TRACE_PROCESSOR}" "${DIST}/Contents/Resources/trace_processor_shell"
/bin/chmod 755 "${DIST}/Contents/Resources/trace_processor_shell"
[[ "$(/usr/bin/shasum -a 256 "${DIST}/Contents/Resources/trace_processor_shell" | /usr/bin/awk '{print $1}')" == "d29864d1ba3b36855527bb1b0ca3aa7f703cdce338b9680bb922c5c151b358fa" ]] || {
  print -u2 "Packaged Perfetto trace_processor failed its pinned SHA-256 receipt."
  exit 1
}

# Package a TFTMAC-owned Mac application host for Android Emulator. Launching
# this nested app with /usr/bin/open keeps the emulator and ADB identity inside
# the logged-in user's macOS session, matching the proven donor architecture.
HOST_APP="${DIST}/Contents/Resources/TFTMAC Emulator Host.app"
HOST_MACOS="${HOST_APP}/Contents/MacOS"
/bin/mkdir -p "${HOST_MACOS}"
/usr/bin/xcrun --sdk macosx clang \
  -Os -arch arm64 -mmacosx-version-min=15.0 \
  "${ROOT}/RuntimeHost/main.c" \
  -o "${HOST_MACOS}/TFTMACEmulatorHost"
/bin/cp "${ROOT}/RuntimeHost/Info.plist" "${HOST_APP}/Contents/Info.plist"
/usr/bin/plutil -lint "${HOST_APP}/Contents/Info.plist" >/dev/null
/usr/bin/codesign --force --sign "${SIGNING_IDENTITY_HASH}" --timestamp=none "${HOST_APP}"

/usr/bin/codesign --force --deep --sign "${SIGNING_IDENTITY_HASH}" --timestamp=none "${DIST}"
/usr/bin/codesign --verify --deep --strict --verbose=2 "${DIST}"
/usr/bin/codesign -dvv "${DIST}" 2>&1 \
  | /usr/bin/grep -F "Authority=${SIGNING_IDENTITY_NAME}" >/dev/null

echo "Native TFTMAC built: ${DIST}"
