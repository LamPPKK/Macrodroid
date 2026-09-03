#!/bin/zsh
set -euo pipefail

# TFTMAC's Android runtime intentionally lives on a removable volume. macOS
# associates that consent with the app's code-signing identity, so ad-hoc
# signing causes the prompt to return after every changed build. This creates a
# stable, local-only identity in the current user's login keychain. It is not a
# distribution or notarization identity.
readonly IDENTITY_NAME="TFTMAC Local Code Signing"
readonly LOGIN_KEYCHAIN="$(/usr/bin/security default-keychain -d user \
  | /usr/bin/sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//')"

identity_hash() {
  /usr/bin/security find-identity -v -p codesigning "${LOGIN_KEYCHAIN}" \
    | /usr/bin/awk -v name="${IDENTITY_NAME}" 'index($0, "\"" name "\"") { print $2; exit }'
}

existing_hash="$(identity_hash)"
if [[ -n "${existing_hash}" ]]; then
  echo "${existing_hash}"
  exit 0
fi

if /usr/bin/security find-certificate -c "${IDENTITY_NAME}" "${LOGIN_KEYCHAIN}" >/dev/null 2>&1; then
  print -u2 "TFTMAC signing certificate exists but is not a valid code-signing identity. Repair it in Keychain Access before rebuilding."
  exit 1
fi

readonly OPENSSL="${TFTMAC_OPENSSL:-/opt/homebrew/bin/openssl}"
[[ -x "${OPENSSL}" ]] || {
  print -u2 "TFTMAC requires OpenSSL at ${OPENSSL} to create its one-time local signing identity."
  exit 1
}

work_dir="$(/usr/bin/mktemp -d /private/tmp/tftmac-local-signing.XXXXXX)"
cleanup() {
  /bin/rm -rf "${work_dir}"
}
trap cleanup EXIT

passphrase="$(/usr/bin/uuidgen)$(/usr/bin/uuidgen)"
umask 077
"${OPENSSL}" req -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
  -subj "/CN=${IDENTITY_NAME}/O=TFTMAC Local Development" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=codeSigning" \
  -keyout "${work_dir}/identity.key" \
  -out "${work_dir}/identity.pem" >/dev/null 2>&1
"${OPENSSL}" pkcs12 -export -legacy \
  -inkey "${work_dir}/identity.key" \
  -in "${work_dir}/identity.pem" \
  -name "${IDENTITY_NAME}" \
  -passout "pass:${passphrase}" \
  -out "${work_dir}/identity.p12"

/usr/bin/security import "${work_dir}/identity.p12" \
  -k "${LOGIN_KEYCHAIN}" \
  -P "${passphrase}" \
  -T /usr/bin/codesign >/dev/null
/usr/bin/security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "${LOGIN_KEYCHAIN}" \
  "${work_dir}/identity.pem"

created_hash="$(identity_hash)"
[[ -n "${created_hash}" ]] || {
  print -u2 "TFTMAC created the certificate but macOS did not expose a valid signing identity."
  exit 1
}
echo "${created_hash}"
