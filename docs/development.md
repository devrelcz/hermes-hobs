# Development

How to build, run and test HobCrew. For what the app does, see the
[README](../README.md). For how it works inside, see
[how-it-works.md](how-it-works.md).

## Platforms

HobCrew is a Flutter app. It ships for iOS, Android and macOS, and the
same code can be built for Windows and Linux too.

Web is not a target: browser CORS and cookie rules block cross-origin access
to the dashboard.

## Run

```bash
flutter pub get
flutter run -d macos   # or an iOS simulator / Android device
```

Enter the dashboard's address, then sign in with its username and password
(provider `basic`).

## Install a release build on Android

To put a numbered release build on an Android phone over adb:

```bash
tool/install_android.sh
```

The build number is the commit count, and Settings > About shows it with
the commit and the build time, so you can tell which build is installed.

## Google Play

`tool/build_play.sh` builds the signed App Bundle. Signing, the store listing
and the App content answers are in [google-play.md](google-play.md).

## Demo server

The in-app demo (*Try the demo* on the sign-in screen) runs a stand-in Hermes
server on the phone itself. Google Play's reviewers use it too. See
[how-it-works.md](how-it-works.md#demo-mode) for details.

To use the same data from another device, `tool/demo_server.dart` serves it
on your machine:

```bash
dart run tool/demo_server.dart
```

Sign in to `http://127.0.0.1:8765` as `u` / `p`. Pass a port as the first
argument to use another one.

## Test

```bash
flutter test
```

The tests run the whole flow against a fake Hermes server
(`test/fake_hermes_server.dart`).

## Layout

- `lib/api/hermes_http.dart`: cookie-aware REST client (dart:io)
- `lib/api/hermes_rpc.dart`: `/api/ws` JSON-RPC client (ticket, heartbeat, reconnect, server requests)
- `lib/state/chat_controller.dart`: one conversation, event → message model
- `lib/state/group_chat_controller.dart`: one group chat (room state, log, sending, member status)
- `lib/state/app_state.dart`: login, biometric lock, Hob list, chats per Hob
- `lib/state/credentials_store.dart`: saved accounts; per-account cookies and password in secure storage
- `lib/state/biometrics.dart`: `local_auth` wrapper (which biometric, prompt)
- `lib/state/notifications.dart`: local notifications, iOS background time
- `lib/api/attachments.dart`: attachment model, `@image:`/`@file:`/`@url:` refs, turn preparation
- `lib/state/composer_draft.dart`: uploads per Hob (progress, cancel, retry); `image_prep.dart` downscales photos
- `lib/state/share_inbox.dart`: shares from other apps waiting for a Hob
- `lib/ui/accounts_ui.dart`: account switcher pieces, Add server, Settings > Accounts
- `lib/ui/`: login, Hob list (split view on wide screens), chat
- `test/`: fake Hermes server covering the whole flow
- `tool/demo_server.dart`: demo data for screenshots and manual testing
