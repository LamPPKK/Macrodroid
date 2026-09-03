#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE

readonly ROOT="${0:A:h:h}"
cd "$ROOT"

fail() {
  print -u2 "TFTMAC installed-runtime verification failed: $*"
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is unavailable: $1"
}

# Local-host contract only. This script intentionally examines machine state
# that repository verification and GitHub CI must never require.
for tool in codesign jq plutil security shasum; do
  require_command "$tool"
done

readonly AUTHORITY="ssot/runtime-authority.json"
[[ -f "$AUTHORITY" ]] || fail "runtime authority is missing"
jq -e '.finalInstalledRelease and .currentHostAudit' "$AUTHORITY" >/dev/null \
  || fail "release or current-host audit authority is missing"

readonly INSTALLED_APP="$(jq -r '.finalInstalledRelease.path' "$AUTHORITY")"
readonly RUNTIME_ROOT="$(jq -r '.runtimeRoot' "$AUTHORITY")"
readonly SDK_ROOT="$(jq -r '.sdkRoot' "$AUTHORITY")"
readonly INFO="${INSTALLED_APP}/Contents/Info.plist"
readonly EXECUTABLE="${INSTALLED_APP}/Contents/MacOS/TFTMAC"
readonly HOST_EXECUTABLE="${INSTALLED_APP}/Contents/Resources/TFTMAC Emulator Host.app/Contents/MacOS/TFTMACEmulatorHost"
readonly ICON_1024="${INSTALLED_APP}/Contents/Resources/TFTMAC-1024.png"
readonly ICON_ICNS="${INSTALLED_APP}/Contents/Resources/TFTMAC.icns"
readonly EMULATOR="${SDK_ROOT}/emulator/emulator"
readonly ADB="${SDK_ROOT}/platform-tools/adb"
readonly INSTALLED_PROTO="$(jq -r '.emulatorController.installedPath' "$AUTHORITY")"

[[ -d "$INSTALLED_APP" ]] || fail "released native app is not installed: $INSTALLED_APP"
[[ -d "$RUNTIME_ROOT" && -d "$SDK_ROOT" ]] || fail "external Android runtime is unavailable: $RUNTIME_ROOT"
for artifact in "$INFO" "$EXECUTABLE" "$HOST_EXECUTABLE" "$ICON_1024" "$ICON_ICNS" "$EMULATOR" "$ADB" "$INSTALLED_PROTO"; do
  [[ -s "$artifact" ]] || fail "required installed artifact is missing or empty: $artifact"
done

[[ "$(plutil -extract CFBundleShortVersionString raw "$INFO")" == "$(jq -r '.finalInstalledRelease.version' "$AUTHORITY")" ]] \
  || fail "installed app version differs from release authority"
[[ "$(plutil -extract CFBundleVersion raw "$INFO")" == "$(jq -r '.finalInstalledRelease.build' "$AUTHORITY")" ]] \
  || fail "installed app build differs from release authority"
[[ "$(shasum -a 256 "$EXECUTABLE" | awk '{print $1}')" == "$(jq -r '.finalInstalledRelease.executableSHA256' "$AUTHORITY")" ]] \
  || fail "installed executable hash differs from historical release authority"
[[ "$(shasum -a 256 "$HOST_EXECUTABLE" | awk '{print $1}')" == "$(jq -r '.finalInstalledRelease.emulatorHostExecutableSHA256' "$AUTHORITY")" ]] \
  || fail "installed emulator-host hash differs from historical release authority"
[[ "$(shasum -a 256 "$ICON_1024" | awk '{print $1}')" == "$(jq -r '.finalInstalledRelease.officialIcon1024SHA256' "$AUTHORITY")" ]] \
  || fail "installed 1024px icon differs from release authority"
[[ "$(shasum -a 256 "$ICON_ICNS" | awk '{print $1}')" == "$(jq -r '.finalInstalledRelease.embeddedIconICNSSHA256' "$AUTHORITY")" ]] \
  || fail "installed ICNS differs from release authority"
[[ "$(shasum -a 256 "$INSTALLED_PROTO" | awk '{print $1}')" == "$(jq -r '.emulatorController.sha256' "$AUTHORITY")" ]] \
  || fail "installed EmulatorController protocol differs from runtime authority"
[[ "$(jq -r '.currentHostAudit.releaseIdentityHashesMatch' "$AUTHORITY")" == "true" ]] \
  || fail "current-host audit does not confirm the release identity hashes"

readonly SIGNING_IDENTITY="$(jq -r '.finalInstalledRelease.signingIdentity' "$AUTHORITY")"
readonly IDENTITY_COUNT="$(security find-identity -v -p codesigning | awk -v name="$SIGNING_IDENTITY" 'index($0, "\"" name "\"") { count += 1 } END { print count + 0 }')"
integer CURRENT_HOST_BLOCKED=0
if [[ "$IDENTITY_COUNT" -eq 0 ]]; then
  print -u2 "Current-host signing blocker: zero available '${SIGNING_IDENTITY}' code-signing identities."
  CURRENT_HOST_BLOCKED=1
fi

SIGNATURE_OUTPUT=""
if ! SIGNATURE_OUTPUT="$(codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP" 2>&1)"; then
  print -u2 -- "$SIGNATURE_OUTPUT"
  CURRENT_HOST_BLOCKED=1
fi

if [[ "$CURRENT_HOST_BLOCKED" -ne 0 ]]; then
  print -u2 "Recorded audit: $(jq -r '.currentHostAudit.observedAt + " — " + .currentHostAudit.cssmError' "$AUTHORITY")"
  fail "installed release hashes match, but current-host signing trust is not passing"
fi

print "TFTMAC installed-runtime verification: OK"
