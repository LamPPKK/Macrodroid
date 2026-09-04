#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE

readonly ROOT="${0:A:h:h}"
cd "$ROOT"

fail() {
  print -u2 "TFTMAC source validation failed: $*"
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is unavailable: $1"
}

# Repository/CI contract. It deliberately has no dependency on
# /Applications/TFTMAC.app, the external emulator runtime, a signing identity,
# user credentials, or a private capture. Those checks belong to the separate
# local-only verify-installed-runtime.command contract.
for tool in git jq node plutil rg shasum xcodebuild zsh; do
  require_command "$tool"
done

readonly INFO="tftmac/Info.plist"
readonly PACKAGE_RESOLVED="TFTMAC.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
readonly PROTO="Vendor/AndroidEmulator/emulator_controller.proto"
readonly PROTO_SOURCE="Vendor/AndroidEmulator/SOURCE.json"

for required in \
  TFTMAC.xcodeproj/project.pbxproj \
  TFTMAC.xcodeproj/xcshareddata/xcschemes/TFTMAC.xcscheme \
  "$INFO" \
  "$PACKAGE_RESOLVED" \
  "$PROTO" \
  "$PROTO_SOURCE" \
  tftmac/Assets/TFTMAC-Official-Icon.png \
  Generated/EmulatorController/emulator_controller.pb.swift \
  Generated/EmulatorController/emulator_controller.grpc.swift \
  scripts/generate-emulator-proto.command \
  scripts/build-tftmac-app.command \
  scripts/build-native-app.command \
  scripts/install-trace-processor.command \
  scripts/ensure-local-signing-identity.command \
  scripts/test-native-app.command \
  scripts/verify-installed-runtime.command \
  ssot/AUTHORITY_INPUTS.sha256 \
  ssot/STACK.lock.yaml \
  ssot/runtime-authority.json \
  ssot/retained-evidence-index.json \
  ssot/TFTMAC_ENGINEERING_MAP.sql \
  ssot/TFTMAC_PERFORMANCE_LAB.sql; do
  [[ -f "$required" ]] || fail "required file is missing: $required"
done

plutil -lint "$INFO" >/dev/null || fail "Info.plist is invalid"
[[ "$(plutil -extract CFBundleDisplayName raw "$INFO")" == "TFTMAC" ]] || fail "unexpected app display name"
[[ "$(plutil -extract CFBundleExecutable raw "$INFO")" == "TFTMAC" ]] || fail "unexpected app executable"
[[ "$(plutil -extract CFBundleIdentifier raw "$INFO")" == "com.flashls1.tftmac" ]] || fail "unexpected bundle identifier"
readonly INFO_VERSION="$(plutil -extract CFBundleShortVersionString raw "$INFO")"
readonly INFO_BUILD="$(plutil -extract CFBundleVersion raw "$INFO")"
readonly AUTHORITY_VERSION="$(jq -r '.finalInstalledRelease.version' ssot/runtime-authority.json)"
readonly AUTHORITY_BUILD="$(jq -r '.finalInstalledRelease.build' ssot/runtime-authority.json)"
[[ "$INFO_VERSION" == "$AUTHORITY_VERSION" ]] || fail "source and release-authority versions differ"
[[ "$INFO_BUILD" == "$AUTHORITY_BUILD" ]] || fail "source and release-authority builds differ"
[[ "$(plutil -extract NSRemovableVolumesUsageDescription raw "$INFO")" == *"Android emulator runtime"* ]] \
  || fail "removable-volume purpose string is missing"

# There is one executable build authority. The compatibility entrypoint may
# delegate to it, but it may never rebuild or install the retired Node shell.
rg -q -F 'scripts/build-native-app.command' scripts/build-tftmac-app.command \
  || fail "compatibility build entrypoint does not delegate to the native build"
if rg -n 'tftmac/Sources|tftmac-direct-control|5040|5592|swiftc' scripts/build-tftmac-app.command; then
  fail "compatibility build entrypoint still contains a retired build/runtime path"
fi
if rg -n 'TFTMACRuntimeBridge|TFTMACViews|TFTMACWindowCoordinator' TFTMAC.xcodeproj/project.pbxproj; then
  fail "native Xcode target references the retired Node shell"
fi

jq -e '
  .schema == 3 and .result == "PASS" and
  .resultScope == "HISTORICAL_RELEASE_AND_LIVE_RUNTIME_ACCEPTANCE; SEE currentHostAudit FOR CURRENT SIGNING TRUST" and
  .emulator.avd == "TFT_Ultra_Tablet" and
  .emulator.adbSerial == "emulator-5582" and
  .emulator.adbServerPort == 5038 and
  .emulator.consolePort == 5582 and
  .emulator.adbVendorKeysInjected == false and
  .runtimeProfile.vcpu == 6 and
  .runtimeProfile.ramMiB == 5120 and
  .runtimeProfile.display == "1920x1080" and
  .runtimeProfile.densityDpi == 320 and
  .runtimeProfile.refreshHz == 60 and
  .runtimeProfile.tftGraphicsQuality == "High" and
  .runtimeProfile.tftFrameRateCap == 60 and
  .runtimeProfile.tftPerformanceModeBeta == false and
  .runtimeProfile.activeExperiment == "combat_latency_a" and
  .finalInstalledRelease.version == "2.3.0" and
  .finalInstalledRelease.build == "8" and
  .finalInstalledRelease.receiptScope == "HISTORICAL_BUILD8_RELEASE_ACCEPTANCE" and
  .finalInstalledRelease.deepCodeSignatureValidScope == "AT_RELEASE_ACCEPTANCE" and
  .finalInstalledRelease.nativeVerifier == "PASS_AT_RELEASE_ACCEPTANCE" and
  .finalInstalledRelease.executableSHA256 == "d3bf7c249a3e5f11b81f778b063e1a8cfe2e7fdeec0537ee6bd8447b1c2268d2" and
  .finalInstalledRelease.emulatorHostExecutableSHA256 == "ea028ec1d74cc025638c2a0e5f8c783748803c1b0ba9012962c038251fb3eb63" and
  .finalInstalledRelease.officialIconSourceSHA256 == "d6ba9ceb76c4b1e44e87f059f775a0ed629f9bea29b0dd73245853d7dca3a016" and
  .finalInstalledRelease.officialIcon1024SHA256 == "ed5fd83efa6e04599e82ca00f897b09813cdeac007850f6993efd601a730345f" and
  .finalInstalledRelease.embeddedIconICNSSHA256 == "010729a19f165b68edeb1fb44e8c31e450f79b3a988c95b8de090373378f6f06" and
  .finalInstalledRelease.signingIdentity == "TFTMAC Local Code Signing" and
  .finalInstalledRelease.adHocSigned == false and
  .finalInstalledRelease.removableVolumePermissionRetainedAcrossRelaunch == true and
  .finalInstalledRelease.nonErrorUnlockOverlayVisible == false and
  .finalInstalledRelease.unitTestsPassed == 43 and
  .finalInstalledRelease.gameModeEligible == true and
  .finalInstalledRelease.guestGameplayPowerGate == true and
  .finalInstalledRelease.primaryInputTransport == "EmulatorController.sendTouch" and
  .androidWebView.currentVersion == "151.0.7922.199"
' ssot/runtime-authority.json >/dev/null || fail "native runtime authority drifted"

jq -e '
  .finalInstalledRelease.currentReleaseGameplayBenchmark == "VERIFIED_CAPTURE_ROOT_ATTRIBUTION_UNKNOWN" and
  .currentHostAudit.releaseIdentityHashesMatch == true and
  .currentHostAudit.zeroIdentityFindings == true and
  .currentHostAudit.trustEvaluation == "NOT_TRUSTED_BY_CURRENT_HOST_POLICY" and
  .currentHostAudit.cssmError == "CSSMERR_TP_NOT_TRUSTED" and
  .currentHostAudit.installedRuntimeVerifier == "BLOCKED_SIGNING_IDENTITY" and
  .currentGameplayCapture.captureId == "2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200" and
  .currentGameplayCapture.storage == "PRIVATE_LOCAL_ONLY" and
  .currentGameplayCapture.database.byteCount == 63897600 and
  .currentGameplayCapture.database.sha256 == "c1ef9c9ffe591a297cb86660e3ccfea7e9aeb593f22100e4e732b2fc77d4ee77" and
  .currentGameplayCapture.graphicsRun.duration == "42m27s" and
  .currentGameplayCapture.graphicsRun.exactLayerCoveragePercent == 99.629 and
  .currentGameplayCapture.graphicsRun.frameIntervalCount == 144364 and
  .currentGameplayCapture.graphicsRun.degradationIncidentCount == 189 and
  .currentGameplayCapture.graphicsRun.weightedFps == 56.98 and
  .currentGameplayCapture.graphicsRun.fpsOnePercentLow == 21.49 and
  .currentGameplayCapture.graphicsRun.p95FrameIntervalMs == 21.51 and
  .currentGameplayCapture.graphicsRun.p99FrameIntervalMs == 33.434 and
  .currentGameplayCapture.effectiveStackReceipt == "UNREAL_DIRECT_VULKAN -> GFXSTREAM_ASG -> HOST_VULKAN -> MOLTENVK -> METAL" and
  .currentGameplayCapture.angleStatus == "CONDITIONAL_NOT_ASSUMED_FOR_TFT_MAIN_RENDERING_PATH" and
  .currentGameplayCapture.macPresenter == "EXCLUDED_FROM_CAUSAL_CANDIDATES_CONTEXT_ONLY" and
  .currentGameplayCapture.markersAndBattles == "OPTIONAL_ANNOTATIONS_NOT_VALIDITY_OR_CAUSAL_GATES" and
  .currentGameplayCapture.automaticLogging == "VERIFIED_PID_LAYER_LIFETIME" and
  .currentGameplayCapture.rootAttribution == "UNKNOWN_UPSTREAM_OF_OR_AT_GUEST_SURFACE" and
  .currentGameplayCapture.nextLayer == "ADVANCED_SOURCE_CAUSAL_LOGGER_PLANNED" and
  .diagnosticRuntimeEligibility.repository == "flashls1/tftmac-runtime" and
  .diagnosticRuntimeEligibility.commit == "c8aa26ebaa5b977965eb165ad8aac5c98408469f" and
  .diagnosticRuntimeEligibility.normalPlayAuthority == "STOCK_BUILD8"
' ssot/runtime-authority.json >/dev/null || fail "current Build 8 capture or diagnostic-runtime authority drifted"

jq -e '
  .schema == 2 and
  any(.externalPrivateEvidence[];
    .id == "capture-2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200" and
    .classification == "PRIVATE_LOCAL_CAPTURE_METADATA_ONLY" and
    .byteCount == 63897600 and
    .sha256 == "c1ef9c9ffe591a297cb86660e3ccfea7e9aeb593f22100e4e732b2fc77d4ee77" and
    .rawDatabaseCommitted == false)
' ssot/retained-evidence-index.json >/dev/null || fail "retained private-evidence receipt drifted"

for locked in \
  'mode: "released_native_runtime"' \
  'avd_name: "TFT_Ultra_Tablet"' \
  'emulator_console_port: 5582' \
  'adb_serial: "emulator-5582"' \
  'adb_server_port: 5038' \
  'ram_mb: 5120' \
  'selected: A' \
  'version: "2.3.0"' \
  'build: "8"' \
  'official_icon_source_sha256: "d6ba9ceb76c4b1e44e87f059f775a0ed629f9bea29b0dd73245853d7dca3a016"' \
  'official_icon_1024_sha256: "ed5fd83efa6e04599e82ca00f897b09813cdeac007850f6993efd601a730345f"' \
  'embedded_icon_icns_sha256: "010729a19f165b68edeb1fb44e8c31e450f79b3a988c95b8de090373378f6f06"' \
  'mac_icon_embedded: true' \
  'removable_volume_permission_relaunch: PASS' \
  'non_error_unlock_overlay: ABSENT' \
  'unit_tests_passed: 43' \
  'webview_version: "151.0.7922.199"' \
  'build8_gameplay_benchmark: "VERIFIED_CAPTURE_ROOT_ATTRIBUTION_UNKNOWN"' \
  'receipt_scope: "historical_build8_release_acceptance"' \
  'native_verifier_at_release_acceptance: PASS' \
  'release_identity_hashes_match: true' \
  'zero_identity_findings: true' \
  'cssm_error: "CSSMERR_TP_NOT_TRUSTED"' \
  'installed_runtime_verifier: "BLOCKED_SIGNING_IDENTITY"' \
  'id: "2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200"' \
  'advanced_source_causal_logger: "planned"'; do
  rg -q -F -- "$locked" ssot/STACK.lock.yaml || fail "active stack lock drifted: $locked"
done

readonly STACK_RUNTIME_AUTHORITY_SHA="$(awk -F'"' '/^[[:space:]]*runtime_authority_sha256:/ {print $2}' ssot/STACK.lock.yaml)"
readonly STACK_AUTHORITY_INPUTS_SHA="$(awk -F'"' '/^[[:space:]]*authority_inputs_sha256:/ {print $2}' ssot/STACK.lock.yaml)"
readonly ACTUAL_RUNTIME_AUTHORITY_SHA="$(shasum -a 256 ssot/runtime-authority.json | awk '{print $1}')"
readonly ACTUAL_AUTHORITY_INPUTS_SHA="$(shasum -a 256 ssot/AUTHORITY_INPUTS.sha256 | awk '{print $1}')"
[[ "$STACK_RUNTIME_AUTHORITY_SHA" == "$ACTUAL_RUNTIME_AUTHORITY_SHA" ]] || fail "STACK runtime-authority hash drifted"
[[ "$STACK_AUTHORITY_INPUTS_SHA" == "$ACTUAL_AUTHORITY_INPUTS_SHA" ]] || fail "STACK authority-input manifest hash drifted"

while read -r expected_hash authority_path; do
  [[ -z "${expected_hash:-}" || "$expected_hash" == \#* ]] && continue
  [[ -f "$authority_path" ]] || fail "authority input is missing: $authority_path"
  actual_hash="$(shasum -a 256 "$authority_path" | awk '{print $1}')"
  [[ "$actual_hash" == "$expected_hash" ]] || fail "authority input hash drifted: $authority_path"
done < ssot/AUTHORITY_INPUTS.sha256

readonly TEST_FUNCTION_COUNT="$(rg -n '^[[:space:]]*func test' Tests/TFTMACTests --glob '*.swift' | wc -l | tr -d '[:space:]')"
[[ "$TEST_FUNCTION_COUNT" == "43" ]] || fail "native test inventory drifted: expected 43, found $TEST_FUNCTION_COUNT"
[[ "$(plutil -extract LSSupportsGameMode raw "$INFO")" == "true" ]] \
  || fail "native app is not eligible for macOS Game Mode"
[[ "$(shasum -a 256 tftmac/Assets/TFTMAC-Official-Icon.png | awk '{print $1}')" == "d6ba9ceb76c4b1e44e87f059f775a0ed629f9bea29b0dd73245853d7dca3a016" ]] \
  || fail "official TFTMAC icon source hash drifted"

readonly PROTO_SHA="$(shasum -a 256 "$PROTO" | awk '{print $1}')"
readonly RECORDED_PROTO_SHA="$(jq -r '.vendoredProtoSHA256' "$PROTO_SOURCE")"
readonly RECORDED_INSTALLED_SHA="$(jq -r '.installedProtoSHA256' "$PROTO_SOURCE")"
[[ "$PROTO_SHA" == "$RECORDED_PROTO_SHA" ]] || fail "vendored EmulatorController proto hash drift"
[[ "$PROTO_SHA" == "$RECORDED_INSTALLED_SHA" ]] || fail "vendored proto no longer matches frozen installed-runtime authority"
jq -e '.schema == 1 and .authority == "INSTALLED_ANDROID_EMULATOR" and .vendoredProtoPath == "Vendor/AndroidEmulator/emulator_controller.proto" and .generator.protocVersion == "36.0" and .generator.swiftProtobufVersion == "1.38.1" and .generator.grpcSwiftProtobufVersion == "2.4.1"' "$PROTO_SOURCE" >/dev/null \
  || fail "EmulatorController provenance is invalid"

readonly GENERATED_PB_SHA="$(shasum -a 256 Generated/EmulatorController/emulator_controller.pb.swift | awk '{print $1}')"
readonly GENERATED_GRPC_SHA="$(shasum -a 256 Generated/EmulatorController/emulator_controller.grpc.swift | awk '{print $1}')"
[[ "$GENERATED_PB_SHA" == "$(jq -r '.generatedSources["Generated/EmulatorController/emulator_controller.pb.swift"]' "$PROTO_SOURCE")" ]] || fail "generated Swift protobuf source drift"
[[ "$GENERATED_GRPC_SHA" == "$(jq -r '.generatedSources["Generated/EmulatorController/emulator_controller.grpc.swift"]' "$PROTO_SOURCE")" ]] || fail "generated Swift gRPC source drift"

jq -e '
  .version == 3 and
  any(.pins[]; .identity == "grpc-swift-2" and .state.version == "2.4.2") and
  any(.pins[]; .identity == "grpc-swift-nio-transport" and .state.version == "2.9.1") and
  any(.pins[]; .identity == "grpc-swift-protobuf" and .state.version == "2.4.1") and
  any(.pins[]; .identity == "swift-protobuf" and .state.version == "1.38.1")
' "$PACKAGE_RESOLVED" >/dev/null || fail "SwiftPM authority pins drifted"

while IFS= read -r script; do
  zsh -o NO_BG_NICE -n "$script" || fail "zsh syntax failed: $script"
done < <(find scripts -type f \( -name '*.command' -o -name '*.sh' \) | LC_ALL=C sort)

node --check tools/tftmac-direct-control.mjs >/dev/null
[[ ! -f tools/tftmac-v2.mjs ]] || node --check tools/tftmac-v2.mjs >/dev/null
node tools/tftmac-direct-control.mjs engineering-map-selftest >/dev/null
node tools/tftmac-direct-control.mjs lab-selftest >/dev/null

if [[ -n "${TFTMAC_FORBIDDEN_TOKEN:-}" ]]; then
  if git ls-files | rg -i -F -- "$TFTMAC_FORBIDDEN_TOKEN"; then
    fail "forbidden retired-product token remains in a tracked path"
  fi
  if git grep -n -i -F -- "$TFTMAC_FORBIDDEN_TOKEN"; then
    fail "forbidden retired-product token remains in tracked content"
  fi
fi

if git ls-files | rg -i '\.(apk|apks|xapk|aab|obb|qcow2|p12|pfx|jks|keystore|mobileprovision|sqlite|sqlite3|db|perfetto-trace|trace|pcap|dmp)$'; then
  fail "private, generated, credential, or raw runtime artifact is tracked"
fi
if git ls-files | rg -i '(^|/)(captures?|screenshots?|login[-_]?probes?|ocr[-_]?probes?|recovery[-_]?apps?|avd[-_]?data)(/|$)'; then
  fail "private capture, screenshot, login/OCR probe, recovery app, or AVD data is tracked"
fi

git diff --check
git diff --cached --check

readonly STATE_DIR="$(mktemp -d /private/tmp/tftmac-source-verify.XXXXXX)"
readonly STATE_BEFORE="${STATE_DIR}/before"
readonly STATE_AFTER="${STATE_DIR}/after"
cleanup() {
  /bin/rm -rf "$STATE_DIR"
}
trap cleanup EXIT
git status --porcelain=v1 --untracked-files=all > "$STATE_BEFORE"

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d /Applications/Xcode-26.6.0.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
  else
    export DEVELOPER_DIR="$(xcode-select -p)"
  fi
fi
readonly RELEASE_DERIVED="${ROOT}/.build/native-ci-release"
/usr/bin/xcodebuild \
  -quiet \
  -project "${ROOT}/TFTMAC.xcodeproj" \
  -scheme TFTMAC \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$RELEASE_DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  build
[[ -x "${RELEASE_DERIVED}/Build/Products/Release/TFTMAC.app/Contents/MacOS/TFTMAC" ]] \
  || fail "unsigned Release build did not produce the TFTMAC executable"

/bin/zsh scripts/test-native-app.command

git status --porcelain=v1 --untracked-files=all > "$STATE_AFTER"
cmp -s "$STATE_BEFORE" "$STATE_AFTER" || {
  diff -u "$STATE_BEFORE" "$STATE_AFTER" || true
  fail "source verification changed tracked or visible generated state"
}

print "TFTMAC source validation: OK (unsigned Release build; 43 native tests)"
