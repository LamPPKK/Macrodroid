#!/bin/zsh
set -euo pipefail

readonly ROOT="${0:A:h:h}"
readonly DIST="${ROOT}/dist"
readonly APP="${DIST}/Macrodroid.app"

print -u2 "========================================================================"
print -u2 "       📦 MACRODROID RELEASE PACKAGING (DMG & ZIP GENERATOR)            "
print -u2 "========================================================================"

# Step 1: Build the native release application
print -u2 "[1/3] Building native release application..."
/bin/zsh "${ROOT}/scripts/build-native-app.command"

[[ -d "${APP}" ]] || {
  print -u2 "Error: ${APP} does not exist."
  exit 1
}

readonly VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "${APP}/Contents/Info.plist" 2>/dev/null || echo "2.3.0")"
readonly BUILD="$(/usr/bin/plutil -extract CFBundleVersion raw "${APP}/Contents/Info.plist" 2>/dev/null || echo "8")"
readonly TAG="v${VERSION}"
readonly ZIP_NAME="Macrodroid-${TAG}-macOS-Universal.zip"
readonly DMG_NAME="Macrodroid-${TAG}-macOS-Universal.dmg"

# Step 2: Package ZIP archive
print -u2 "[2/3] Packaging distribution ZIP (${ZIP_NAME})..."
/bin/rm -f "${DIST}/${ZIP_NAME}"
/usr/bin/ditto -c -k --keepParent "${APP}" "${DIST}/${ZIP_NAME}"

# Step 3: Package DMG with Applications shortcut
print -u2 "[3/3] Packaging distribution DMG (${DMG_NAME})..."
/bin/rm -f "${DIST}/${DMG_NAME}"
readonly DMG_STAGE="$(mktemp -d /tmp/macrodroid-local-dmg.XXXXXX)"
/bin/cp -R "${APP}" "${DMG_STAGE}/"
/bin/ln -s /Applications "${DMG_STAGE}/Applications"

/usr/bin/hdiutil create \
  -volname "Macrodroid" \
  -srcfolder "${DMG_STAGE}" \
  -ov \
  -format UDZO \
  "${DIST}/${DMG_NAME}" >/dev/null

/bin/rm -rf "${DMG_STAGE}"

# Step 4: Generate Checksums
(
  cd "${DIST}"
  /usr/bin/shasum -a 256 "${ZIP_NAME}" "${DMG_NAME}" > SHA256SUMS.txt
)

print -u2 ""
print -u2 "========================================================================"
print -u2 "🎉 RELEASE PACKAGE COMPLETED SUCCESSFULLY!"
print -u2 "========================================================================"
print -u2 "  Version:  ${VERSION} (Build ${BUILD})"
print -u2 "  App:      ${APP}"
print -u2 "  ZIP:      ${DIST}/${ZIP_NAME} ($(/usr/bin/du -sh "${DIST}/${ZIP_NAME}" | awk '{print $1}'))"
print -u2 "  DMG:      ${DIST}/${DMG_NAME} ($(/usr/bin/du -sh "${DIST}/${DMG_NAME}" | awk '{print $1}'))"
print -u2 "  SHA-256:  ${DIST}/SHA256SUMS.txt"
print -u2 "========================================================================"
print -u2 "Checksums:"
/bin/cat "${DIST}/SHA256SUMS.txt"
print -u2 "========================================================================"
