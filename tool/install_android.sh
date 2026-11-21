#!/usr/bin/env bash
# Builds a release APK and installs it on the phone over adb, numbered so
# Settings > About tells which build is on it: the build number is the
# commit count (always rising, so installs upgrade in place), and the
# commit and build time ride along as --dart-define values.
#
#   tool/install_android.sh            # the only adb device
#   ANDROID_SERIAL=<id> tool/install_android.sh
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=$(git rev-list --count HEAD)
SHA=$(git rev-parse --short HEAD)
# A "+" marks a build with uncommitted changes.
git diff --quiet HEAD -- || SHA="$SHA+"
STAMP=$(date +%Y-%m-%dT%H:%M)

flutter build apk --release \
  --build-number="$BUILD" \
  --dart-define=GIT_SHA="$SHA" \
  --dart-define=BUILD_TIME="$STAMP"
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell monkey -p cz.devrel.hermeshobs -c android.intent.category.LAUNCHER 1 >/dev/null
echo "Installed build $BUILD ($SHA, $STAMP)."
