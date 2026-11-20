# Hermes Hobs

Flutter client (iOS, Android, macOS) for working with your personal Hobs on a Hermes Agent
dashboard (default `https://hermes.devrel.cz`). In Hermes, each **profile** is a Hob.

## Run

```bash
flutter pub get
flutter run -d macos   # or an iOS simulator / Android device
```

Sign in with the dashboard's username and password (provider `basic`).

### Face ID, Touch ID, fingerprint

Settings → Security → *Unlock with Face ID* (or Touch ID / fingerprint; the
switch only shows when the device has one enrolled). Turning it on asks for the
biometric once. Then:

- The app opens behind a lock screen at startup and after a minute in the
  background (`AppState.relockAfter`). The lock covers every open route, so the
  chat you were in is still there after unlocking. The device passcode works as
  a fallback, like on the system lock screen.
- After signing out, the login form no longer prefills the remembered password;
  *Sign in with Face ID* verifies you and signs in with it instead.
- *Sign in with password* on the lock screen signs out, for when the biometric
  is unavailable.

This is an app-level gate (`local_auth`). The password itself stays in the
keychain/keystore as before; it is not bound to the biometric.

## How it talks to Hermes

| Step | Call |
|---|---|
| Login | `POST /auth/password-login` `{provider:"basic",username,password}` → session cookies (`hermes_session_at/rt/provider`). The app stores them and saves every rotated `Set-Cookie`. |
| Hob list | RPC `profiles.list {include_sessions:true}` (REST `GET /api/profiles` as fallback). Folders, title, color, shape and pin come from `ui_meta['hermes-bots']`; preview and time come from `canonical_session`. |
| Chat socket | `POST /api/auth/ws-ticket` (single-use, 30 s) → `wss://…/api/ws?ticket=…`. JSON-RPC 2.0, one object per frame. No `Origin` header is sent. |
| Handshake | the server sends `event gateway.ready`, the client sends `client.capabilities {server_requests:true}`, and the client sends `gateway.ping` every 15 s |
| Hob Chat | Each Hob has one forever-chat: the session titled "Bot Chat". The app opens it with `session.resume` (history included). On a Hob's first chat it calls `session.create {title:"Bot Chat", hidden, follow_profile_config}` followed by `session.title`. |
| Conversation | `prompt.submit {session_id,text}` → events `message.start / message.delta / message.interim / tool.* / message.complete` |
| Control | `session.interrupt`, `config.set {key:"reasoning", scope:"session"}`, `config.get` / `config.set {key:"approvals.mode", profile}` (profile-wide approval mode: manual, smart, off), server requests `approval` (reply with `{choice}`) and `clarify` (reply with `{answers,outcome}`) |
| Folders | Rename: `profiles.configure {name, ui_meta:{"hermes-bots":{…,sectionName}}, ui_meta_expected_revisions}` for every Hob in the folder (the write replaces the whole `hermes-bots` block, so the app sends it back complete). Folder order is local to the device, like on the dashboard. |
| Hob profile | Tapping the Hob's avatar in the chat header opens its profile. Title, shape and color: `profiles.configure` with the whole `hermes-bots` block, like folders. Description: `cli.exec {argv:["profile","describe",name,"--text",…]}`. Model: `profiles.describe {name}` reads it, `model.options` lists providers, `profiles.configure {name, provider, model}` switches it (`confirm_expensive_model` after the server asks); inheriting again is `cli.exec` `config unset model`. SOUL.md: read from `profiles.describe`, replaced with `profiles.configure {name, soul}`. |
| Attachments | Images: `POST /api/chat/image-upload?profile=<hob>` `{data_url, filename}` → `{path, mime_type}` (the profile's `cache/images/`). Files: multipart `POST /api/chat/file-upload?profile=<hob>` (field `file`) → `{path, staged_upload}`, then right before sending `file.attach {session_id, name, staged_upload}` → `{ref_text:"@file:…"}`. Links: an `@url:<url>` line. The submit text is the ref lines, a blank line, then the message (`What do you see in this image?` for images alone). Canonical gateway: `prompt.submit {…, attachments:[{path, mime}]}`; legacy dispatcher: `image.attach {session_id, path}` before the submit. |
| Attachments in history | User rows carry `@image:<path>`, `@file:<path>`, `@url:<url>` lines (values with spaces quoted in backticks); images are read with `GET /api/fs/download?path=…&profile=<hob>`. |
| Scheduled jobs | `cron.manage {action:"list", profile}` (read-only) |
| Reconnect | auto backoff, then `session.resume` with the stored id |

### Attachments and sharing

- The composer's **+** adds a photo from the camera, photos from the library,
  files (up to 16 MB) or a link. iOS and macOS can also paste an image from
  the clipboard; Android keyboards insert clipboard images straight into the
  text field. Folders and prompt snippets from the dashboard are not offered.
- Attachments upload as soon as they are picked, with progress on the
  thumbnail. The cross cancels or removes one; a failed one retries on tap.
  Send stays disabled until every attachment is uploaded.
- Photos are downscaled to 2048 px on the longest side and re-encoded as JPEG
  (quality 85) when larger or in a format the server refuses (HEIC).
- Sent messages, and the history after `session.resume`, show image
  thumbnails (tap for full screen), file chips and links.
- **Share to Hob**: Hermes Hobs is a share target for photos, files, links and
  text (iOS Share Extension in `ios/ShareExtension`, Android `SEND` /
  `SEND_MULTIPLE` intent filters, both through `receive_sharing_intent`).
  The share waits until the Hob list is on screen (signed in, unlocked), asks
  which Hob gets it and opens that chat with everything in the composer.
  Nothing is sent until you tap send.
- iOS setup: the Runner and the extension share the app group
  `group.cz.devrel.hobs` (`CUSTOM_GROUP_ID`); a signed device build needs that
  group registered for the team. The extension writes the hand-over the
  plugin reads and opens `ShareMedia-cz.devrel.hobs:share`.

The SESSIONS tab and group chats from the dashboard are out of scope. Unread
state, collapsed folders and folder order are stored locally on the device.

## Layout

- `lib/api/hermes_http.dart`: cookie-aware REST client (dart:io)
- `lib/api/hermes_rpc.dart`: `/api/ws` JSON-RPC client (ticket, heartbeat, reconnect, server requests)
- `lib/state/chat_controller.dart`: one conversation, event → message model
- `lib/state/app_state.dart`: login, biometric lock, Hob list, chats per Hob
- `lib/state/biometrics.dart`: `local_auth` wrapper (which biometric, prompt)
- `lib/api/attachments.dart`: attachment model, `@image:`/`@file:`/`@url:` refs, turn preparation
- `lib/state/composer_draft.dart`: uploads per Hob (progress, cancel, retry); `image_prep.dart` downscales photos
- `lib/state/share_inbox.dart`: shares from other apps waiting for a Hob
- `lib/ui/`: login, Hob list (split view on wide screens), chat
- `test/`: fake Hermes server covering the whole flow

Web is not a target: browser CORS and cookie rules block cross-origin access to the dashboard.
