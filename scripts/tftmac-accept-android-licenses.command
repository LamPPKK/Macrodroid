#!/bin/zsh
set -euo pipefail

console_user="$(/usr/bin/stat -f '%Su' /dev/console)"
if [[ -z "$console_user" || "$console_user" == "root" || "$console_user" == "loginwindow" ]]; then
  print -u2 "TFTMAC: could not resolve the logged-in macOS user."
  exit 1
fi

user_home="$(/usr/bin/dscl . -read "/Users/$console_user" NFSHomeDirectory | /usr/bin/awk '{print $2}')"
if [[ -z "$user_home" ]]; then
  print -u2 "TFTMAC: could not resolve the logged-in user's home directory."
  exit 1
fi

sdk_root="/Volumes/MAC MINI M4/TFTMAC/Runtime/SDK"
sdkmanager="$sdk_root/cmdline-tools/latest/bin/sdkmanager"

if [[ ! -d "/Volumes/MAC MINI M4" ]]; then
  print -u2 "TFTMAC: /Volumes/MAC MINI M4 is not mounted; refusing to use the internal disk."
  exit 1
fi

if [[ ! -x "$sdkmanager" ]]; then
  print -u2 "TFTMAC: isolated sdkmanager is not installed at:"
  print -u2 "  $sdkmanager"
  print -u2 "Run Phase 0 Android bootstrap first."
  exit 1
fi

java_home="${JAVA_HOME:-}"
if [[ -z "$java_home" || ! -x "$java_home/bin/java" ]]; then
  java_home="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
fi
if [[ -z "$java_home" || ! -x "$java_home/bin/java" ]]; then
  for candidate in \
    "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" \
    "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home" \
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
    "/Applications/Android Studio.app/Contents/jre/Contents/Home"; do
    if [[ -x "$candidate/bin/java" ]]; then
      java_home="$candidate"
      break
    fi
  done
fi
if [[ -z "$java_home" || ! -x "$java_home/bin/java" ]]; then
  print -u2 "TFTMAC: Java 17 runtime not found. Install with: brew install openjdk@17"
  exit 1
fi

export JAVA_HOME="$java_home"
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_SDK_ROOT="$sdk_root"
export ANDROID_HOME="$sdk_root"

cat <<'EOF'
TFTMAC Android SDK license gate

This command is intentionally interactive. Review Google's license text yourself.
Nothing in TFTMAC auto-accepts Android SDK terms on your behalf.

Accept only terms you agree to. When complete, TFTMAC Phase 0 will detect the
license files in its isolated SDK and continue package installation.
EOF

exec "$sdkmanager" --sdk_root="$sdk_root" --licenses
