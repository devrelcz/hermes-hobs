# App Store release

How the HobCrew iOS app is built, signed and published through App Store
Connect: TestFlight first, then the App Store. Bundle ID `com.hobcrew.app`,
share extension `com.hobcrew.app.ShareExtension`, app group
`group.com.hobcrew.app`, team `WHD54925U2` (Apple Developer Program,
Individual, so the seller shown on the store is the account holder's name).

iOS has no download outside the store the way macOS has its DMG: EU web
distribution needs an account that has been in the program for two years
and an app with a million installs in the EU.

The app is iPhone only (`TARGETED_DEVICE_FAMILY = 1`). On an iPad it runs in
the iPhone window, and the listing needs no iPad screenshots.

## Current state

- The project signs automatically with team `WHD54925U2`. The first
  `tool/release_ios.sh --local` (November 26, 2026, build 191) created the
  Apple Distribution certificate, the App IDs and the app group in the
  developer account through Xcode, and exported a signed `.ipa`.
- Not done yet: the app record in App Store Connect, the API key, the first
  upload, the listing and review.

## Set up once

1. **Release Xcode.** App Store Connect refuses builds from a beta Xcode, and
   the script stops when `xcode-select -p` points to one:

   ```bash
   sudo xcode-select -s /Applications/Xcode.app
   ```

2. **App record.** App Store Connect > Apps > + > New App: platform iOS,
   name *HobCrew*, primary language English (U.S.), bundle ID
   `com.hobcrew.app`, SKU `hobcrew-ios`, full access.

3. **API key** for the script. App Store Connect > Users and Access >
   Integrations > App Store Connect API > Team Keys > +, access *App
   Manager*. Download the `.p8` (only once) to
   `~/.appstoreconnect/private_keys/AuthKey_<key id>.p8`, and write the ids to
   `~/.appstoreconnect/hobcrew.env`:

   ```bash
   ASC_KEY_ID=<key id>
   ASC_ISSUER_ID=<issuer id>
   ```

## Build and upload

```bash
tool/release_ios.sh
```

The script refuses a dirty tree (build from a temporary `git worktree` of the
commit to leave work in progress alone). It compiles the Dart code with
`flutter build ios --config-only`, archives with `xcodebuild`, signs with
automatic provisioning through the API key and uploads the build. The build
number is the commit count, the same number the Android and macOS builds of
that commit get; the version comes from `pubspec.yaml`. A version that is
already live on the App Store needs a new version in `pubspec.yaml` first.

`tool/release_ios.sh --local` archives and exports
`build/hobcrew-ios-<version>-<build>-local.ipa` without uploading, signed
through the account in Xcode > Settings > Accounts. Use it to check that the
build signs.

## TestFlight

After processing (about 15 minutes) the build is in TestFlight.
`ITSAppUsesNonExemptEncryption = false` in `Info.plist` answers the export
compliance question (the app only uses HTTPS), so the build is ready to test
without a prompt.

- **Internal testing**: up to 100 people with a role in the App Store Connect
  team, no review.
- **External testing**: up to 10,000 testers by email or public link; the
  first build of each version goes through a short beta review.

## Pairing links

`https://hobcrew.com/pair#<code>` opens the app as a Universal Link: the app
has the `applinks:hobcrew.com` associated domain, and the HobCrew web serves
`/.well-known/apple-app-site-association` for
`WHD54925U2.com.hobcrew.app` with the path `/pair`. The `hobcrew://pair/<code>`
scheme works too. `FlutterDeepLinkingEnabled` is off so the links reach
`app_links` and not Flutter's router (the same as on Android).

## Listing

- **Category**: Productivity. **Price**: free. **Age rating**: answers as on
  Play (no objectionable content, unrestricted web access No, AI-generated
  content from the user's server); result 4+ or 9+.
- **Privacy policy URL**:
  https://github.com/hobcrew-com/hobcrew-app/blob/master/docs/privacy-policy.md
- **Support URL**: https://hobcrew.com. **Marketing URL**: https://hobcrew.com.
- **Texts**: reuse the Play listing texts in
  [google-play.md](google-play.md#store-listing), en-US and cs-CZ. App Store
  has no short description; the subtitle is up to 30 characters.
- **Screenshots**: 6.9" iPhone, 1320x2868 portrait, at least one, up to ten
  per language. Capture the demo in the iOS simulator (iPhone 17 Pro Max)
  with `xcrun simctl io booted screenshot`.
- **App Privacy** (nutrition label), in step with `ios/Runner/PrivacyInfo.xcprivacy`
  and the Play data safety answers: data is collected, none used for
  tracking. Collected, linked to the user, for App Functionality only: User
  ID, Other User Content (messages, files), Photos or Videos.

## Review

- **Sign-in information**: *Sign-in required* off, and in the notes:
  "No account is needed for review. On the sign-in screen tap "Try the demo,
  no server needed". It runs a sample server inside the app with demo Hobs,
  chats and a group chat, and every feature can be reviewed there. Real use
  pairs the app with the user's own HobCrew crew, created on hobcrew.com."
- **Payments (guideline 3.1.1)**: the subscription is sold on hobcrew.com
  through Stripe. The app must not sell, show prices or link to buying; it
  only signs in to a crew the user already has. Keep it that way.
- **Account deletion (guideline 5.1.1(v))**: the app creates no accounts, so
  it needs no deletion flow; removing an account in Settings > Accounts
  deletes its data from the device.
- Review usually takes one to two days. Release: *Manually release this
  version*, so the server side can be checked before it goes out.
