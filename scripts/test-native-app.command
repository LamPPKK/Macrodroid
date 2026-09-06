#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  elif [[ -d /Applications/Xcode-26.6.0.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
  else
    export DEVELOPER_DIR="$(xcode-select -p)"
  fi
fi
DERIVED="${ROOT}/.build/native-tests"

/usr/bin/xcodebuild \
  -quiet \
  -project "${ROOT}/Macrodroid.xcodeproj" \
  -scheme Macrodroid \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED}" \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing

readonly TEST_BUNDLE="${DERIVED}/Build/Products/Debug/MacrodroidTests.xctest"
readonly XCTEST="${DEVELOPER_DIR}/usr/bin/xctest"
[[ -x "${XCTEST}" ]] || { echo "XCTest runner is unavailable: ${XCTEST}" >&2; exit 1; }
[[ -x "${TEST_BUNDLE}/Contents/MacOS/MacrodroidTests" ]] || { echo "Test bundle is incomplete: ${TEST_BUNDLE}" >&2; exit 1; }
"${XCTEST}" "${TEST_BUNDLE}"
