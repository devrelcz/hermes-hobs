#!/usr/bin/env bash
# Builds the signed App Bundle for Google Play, numbered like
# tool/install_android.sh: the build number (versionCode) is the commit
# count, so every upload is higher than the last; the version name comes
# from pubspec.yaml. Needs android/key.properties (docs/google-play.md).
#
#   tool/build_play.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f android/key.properties ]; then
  echo "android/key.properties is missing, see docs/google-play.md." >&2
  exit 1
fi
if ! git diff --quiet HEAD --; then
  echo "Uncommitted changes: commit first so the build matches a commit." >&2
  exit 1
fi

BUILD=$(git rev-list --count HEAD)
SHA=$(git rev-parse --short HEAD)
STAMP=$(date +%Y-%m-%dT%H:%M)

flutter build appbundle --release \
  --build-number="$BUILD" \
  --dart-define=GIT_SHA="$SHA" \
  --dart-define=BUILD_TIME="$STAMP"

AAB=build/app/outputs/bundle/release/app-release.aab
OUT=build/hermes-hobs-$(grep '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')-$BUILD.aab
cp "$AAB" "$OUT"
echo "Built $OUT (versionCode $BUILD, $SHA, $STAMP)."
