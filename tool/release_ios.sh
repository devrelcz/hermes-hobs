#!/usr/bin/env bash
# Builds the iOS app for the App Store and uploads it to App Store Connect,
# where it shows up in TestFlight and can be sent for review. Numbered like
# tool/build_play.sh and tool/release_macos.sh: the build number is the
# commit count, the version name comes from pubspec.yaml.
#
#   tool/release_ios.sh           archive, sign and upload (docs/app-store.md)
#   tool/release_ios.sh --local   archive and export the .ipa without
#                                 uploading; uncommitted changes allowed
#
# Signing is automatic: Xcode creates the Apple Distribution certificate,
# the App IDs, the app group and the provisioning profiles itself. It signs
# in with an App Store Connect API key (Users and Access > Integrations >
# App Store Connect API, role App Manager), set up once:
#
#   ~/.appstoreconnect/private_keys/AuthKey_<key id>.p8
#   ASC_KEY_ID=<key id> ASC_ISSUER_ID=<issuer id>   (environment, or in
#                                                    ~/.appstoreconnect/hobcrew.env)
#
# Without the key (--local only), Xcode uses the account signed in under
# Xcode > Settings > Accounts.
set -euo pipefail
cd "$(dirname "$0")/.."

LOCAL=0
case "${1:-}" in
  "") ;;
  --local) LOCAL=1 ;;
  *) echo "Usage: tool/release_ios.sh [--local]" >&2; exit 1 ;;
esac

ENV_FILE=$HOME/.appstoreconnect/hobcrew.env
# shellcheck source=/dev/null
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

AUTH=()
if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ]; then
  KEY=${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8}
  if [ ! -f "$KEY" ]; then
    echo "API key $KEY is missing, see docs/app-store.md." >&2
    exit 1
  fi
  AUTH=(-authenticationKeyPath "$KEY"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID")
elif [ "$LOCAL" = 0 ]; then
  echo "ASC_KEY_ID and ASC_ISSUER_ID are not set, see docs/app-store.md." >&2
  exit 1
fi

if [ "$LOCAL" = 0 ] && ! git diff --quiet HEAD --; then
  echo "Uncommitted changes: commit first so the build matches a commit." >&2
  exit 1
fi

# App Store Connect refuses builds made with a beta Xcode.
if xcode-select -p | grep -qi beta; then
  echo "xcode-select points to a beta Xcode ($(xcode-select -p))." \
    "Switch to the release one: sudo xcode-select -s /Applications/Xcode.app" >&2
  exit 1
fi

VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')
BUILD=$(git rev-list --count HEAD)
SHA=$(git rev-parse --short HEAD)
STAMP=$(date +%Y-%m-%dT%H:%M)

# Flutter compiles the Dart code and writes the version into the Xcode
# settings; xcodebuild then archives and signs.
flutter build ios --release --config-only \
  --build-number="$BUILD" \
  --dart-define=GIT_SHA="$SHA" \
  --dart-define=BUILD_TIME="$STAMP"

ARCHIVE=build/ios/archive/HobCrew-$VERSION-$BUILD.xcarchive
rm -rf "$ARCHIVE"
xcodebuild archive \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -destination generic/platform=iOS \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} \
  -quiet

DESTINATION=upload
[ "$LOCAL" = 1 ] && DESTINATION=export
OPTIONS=$(mktemp -t hobcrew-export).plist
trap 'rm -f "$OPTIONS"' EXIT
cat >"$OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>$DESTINATION</string>
	<key>teamID</key>
	<string>WHD54925U2</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>uploadSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
EOF

OUT=build/ios/ipa
rm -rf "$OUT"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OPTIONS" \
  -exportPath "$OUT" \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"}

if [ "$LOCAL" = 1 ]; then
  IPA=build/hobcrew-ios-$VERSION-$BUILD-local.ipa
  cp "$(find "$OUT" -maxdepth 1 -name '*.ipa' | head -n 1)" "$IPA"
  echo "Built $IPA (build $BUILD, $SHA), not uploaded."
  exit 0
fi

echo "Uploaded $VERSION ($BUILD, $SHA, $STAMP) to App Store Connect."
echo "It shows up in TestFlight after processing, usually within 15 minutes."
