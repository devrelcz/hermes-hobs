#!/usr/bin/env bash
# Builds the macOS app for download from the web, outside the Mac App Store:
# a release build signed with the Developer ID certificate, packed into a
# disk image, notarized by Apple and stapled, so Gatekeeper opens it without
# a warning. Numbered like tool/build_play.sh: the build number is the commit
# count, the version name comes from pubspec.yaml.
#
#   tool/release_macos.sh           the release (docs/development.md)
#   tool/release_macos.sh --local   try the pipeline: ad-hoc signature, no
#                                   notarization, uncommitted changes allowed
#
# Needs a "Developer ID Application" certificate in the keychain and the
# notarization credentials stored once under a keychain profile:
#
#   xcrun notarytool store-credentials hobcrew-notary \
#     --apple-id <apple id> --team-id <team id>
#
# MACOS_SIGN_IDENTITY picks the certificate when there are several,
# NOTARY_PROFILE names another keychain profile.
set -euo pipefail
cd "$(dirname "$0")/.."

LOCAL=0
case "${1:-}" in
  "") ;;
  --local) LOCAL=1 ;;
  *) echo "Usage: tool/release_macos.sh [--local]" >&2; exit 1 ;;
esac

PROFILE=${NOTARY_PROFILE:-hobcrew-notary}

if [ "$LOCAL" = 1 ]; then
  IDENTITY=-
  # An ad-hoc signature has no team, so the hardened runtime would refuse to
  # load the app's own frameworks, and Apple's timestamp server refuses it.
  SIGN=(--timestamp=none)
else
  if ! git diff --quiet HEAD --; then
    echo "Uncommitted changes: commit first so the build matches a commit." >&2
    exit 1
  fi
  IDENTITY=${MACOS_SIGN_IDENTITY:-$(security find-identity -v -p codesigning |
    sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -n 1)}
  if [ -z "$IDENTITY" ]; then
    echo "No Developer ID Application certificate in the keychain," \
      "see docs/development.md." >&2
    exit 1
  fi
  if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    echo "Notarization credentials '$PROFILE' are missing or rejected," \
      "see docs/development.md." >&2
    exit 1
  fi
  SIGN=(--options runtime --timestamp)
fi

VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')
BUILD=$(git rev-list --count HEAD)
SHA=$(git rev-parse --short HEAD)
STAMP=$(date +%Y-%m-%dT%H:%M)

flutter build macos --release \
  --build-number="$BUILD" \
  --dart-define=GIT_SHA="$SHA" \
  --dart-define=BUILD_TIME="$STAMP"

PRODUCTS=build/macos/Build/Products/Release
APP=$(find "$PRODUCTS" -maxdepth 1 -name '*.app' | head -n 1)
if [ -z "$APP" ]; then
  echo "No .app in $PRODUCTS." >&2
  exit 1
fi
NAME=$(basename "$APP" .app)

# Xcode signs the build ad hoc. Sign again with the hardened runtime, which
# notarization requires: nested code first, the app with its entitlements last.
find "$APP/Contents/Frameworks" -depth \
  \( -name '*.framework' -o -name '*.dylib' \) -print0 |
  while IFS= read -r -d '' CODE; do
    codesign --force "${SIGN[@]}" --sign "$IDENTITY" "$CODE"
  done
codesign --force "${SIGN[@]}" \
  --entitlements macos/Runner/Release.entitlements \
  --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

SUFFIX=
[ "$LOCAL" = 1 ] && SUFFIX=-local
DMG=build/hobcrew-macos-$VERSION-$BUILD$SUFFIX.dmg
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -ov -fs HFS+ -format UDZO \
  -volname "$NAME" -srcfolder "$STAGE" "$DMG"

if [ "$LOCAL" = 1 ]; then
  echo "Built $DMG (build $BUILD, $SHA): ad-hoc signature, not notarized," \
    "Gatekeeper will block it on other Macs."
  exit 0
fi

codesign --force --timestamp --sign "$IDENTITY" "$DMG"

RESULT=$(xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" \
  --wait --output-format json)
STATUS=$(printf '%s' "$RESULT" | plutil -extract status raw -o - -)
if [ "$STATUS" != Accepted ]; then
  ID=$(printf '%s' "$RESULT" | plutil -extract id raw -o - -)
  echo "Notarization ended as $STATUS. Apple's reasons:" >&2
  echo "  xcrun notarytool log $ID --keychain-profile $PROFILE" >&2
  exit 1
fi

xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature "$DMG"

echo "Built $DMG (build $BUILD, $SHA, $STAMP), notarized and stapled."
echo "SHA-256: $(shasum -a 256 "$DMG" | cut -d ' ' -f 1)"
