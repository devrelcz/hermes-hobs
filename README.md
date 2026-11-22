# Hermes Hobs

Talk to your Hobs from wherever you are.

Hermes Hobs is a Flutter app. It ships for iOS, Android and macOS, and the same
code can be built for Windows and Linux too. It signs in to a
Hermes Agent dashboard at the address you enter, where each
**profile** is a Hob, and gives every Hob its own chat.

Hermes Hobs is an unofficial community app. It is not made, endorsed or
supported by Nous Research, the makers of Hermes Agent.

<a href="https://play.google.com/store/apps/details?id=cz.devrel.hermeshobs"><img src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" height="80" alt="Get it on Google Play"></a>

The Android app is on [Google Play](https://play.google.com/store/apps/details?id=cz.devrel.hermeshobs).
No server yet? [Try the demo](#try-it-without-a-server). The
[privacy policy](docs/privacy-policy.md) explains what the app does with your
data.

<p>
  <img src="docs/screenshots/hobs.png" width="200" alt="Hob list with folders, pinned Hobs and a group chat">
  <img src="docs/screenshots/chat.png" width="200" alt="Chat with a Hob, showing tool calls and a formatted reply">
  <img src="docs/screenshots/group.png" width="200" alt="Group chat where three Hobs answer one question">
  <img src="docs/screenshots/profile.png" width="200" alt="Hob profile with face, shape and color pickers">
</p>

## What it does

- **One chat per Hob.** Replies stream in as the Hob writes them, with the
  tools it used. Approve a command or answer a question right in the chat.
- **Tag other Hobs.** Type `@` to pull another Hob into the conversation.
- **Group chats.** Ask 2 to 6 Hobs at once and read their answers in one
  thread.
- **Your list, your way.** Folders, pins, hidden Hobs, and filters for unread,
  pinned, active and recent.
- **Hob profiles.** Change a Hob's face, color, title, description, model and
  SOUL.md.
- **Per-chat settings.** Switch the model, reasoning level and approval mode
  from the composer.
- **Attachments.** Send photos, files up to 16 MB and links, or share them
  into a Hob from any other app.
- **Notifications.** Hear about it when a Hob finishes a reply or waits for
  you, in a Hob chat or a group chat.
- **Offline bar.** Without internet, a bar asks you to turn on Wi-Fi or
  mobile data, and the chats reconnect as soon as it is back.
- **Face ID, Touch ID or fingerprint** lock the app when you leave it.
- Czech and English.

## Run

```bash
flutter pub get
flutter run -d macos   # or an iOS simulator / Android device
```

Enter the dashboard's address, then sign in with its username and password
(provider `basic`).

More than one Hermes server? Tap your avatar and pick *Add server*: each
server is an account with its own name and color, and the avatar menu
switches between them. Only the account you are in is connected and sends
notifications.

To put a numbered release build on an Android phone over adb:

```bash
tool/install_android.sh
```

The build number is the commit count, and Settings > About shows it with
the commit and the build time, so you can tell which build is installed.

For Google Play, `tool/build_play.sh` builds the signed App Bundle; signing,
the store listing and the App content answers are in
[docs/google-play.md](docs/google-play.md).

## Try it without a server

Tap *Try the demo* on the sign-in screen. The app runs a stand-in Hermes
server with the demo data from the screenshots on the phone itself and signs
in to it as an account called Demo. Replies are canned, and the demo starts
fresh each time the app starts. Google Play's reviewers use it too.

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

## Limits

- Notifications are local; there is no push. iOS suspends the app about 30
  seconds after you leave it, so a Hob that answers later notifies you only
  when you open the app again.
- The SESSIONS tab, group chats with Hobs of another gateway (peers), routing
  settings and attachments in group chats are out of scope.
- Unread state, collapsed folders and folder order stay on the device. A
  chat read on another device still shows as unread here, and its
  notification stays; *Mark all as read* in the account menu clears both.
- Web is not a target: browser CORS and cookie rules block cross-origin access
  to the dashboard.

## How it works

[docs/how-it-works.md](docs/how-it-works.md) covers server accounts, the biometric lock, how
notifications reach the app, every call the app makes to Hermes, and
attachments.

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
