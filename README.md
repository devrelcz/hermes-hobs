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

### Notifications

The app fires **local** notifications (`flutter_local_notifications`; no push,
no APNs/FCM, nothing on the server) when a Hob:

- finishes a reply (`message.complete`): the Hob's name and a short preview;
- waits for you: an approval (`approval.request` event or `approval` server
  request) or a question (`clarify.request` / `clarify`). The Hob is blocked
  until someone answers, so these matter most.

It notifies whenever that Hob's chat is not on screen: the app is in the
background (on macOS also when the window is behind other apps), the lock
screen is up, or you are looking at another Hob or at the list. One
notification per Hob; a newer one replaces it and opening the chat clears it.
Replies and prompts that `session.resume` replays after a reconnect don't
notify again (each prompt id / turn notifies once); a prompt that first shows
up in a reconnect snapshot, or a turn that ended with a reply while the socket
was down, does notify.

Tapping a notification opens that Hob's chat (pushed on phones, beside the
list on wide screens). With the biometric lock on, the lock screen comes first
and the chat opens after unlocking.

The system permission is asked for when you send your first prompt, not at
first launch. Settings → Notifications turns them off (stored in
`shared_preferences`, key `notifications`); turning the switch on asks for the
permission again and says so when the system has notifications blocked.
Android 13+ uses `POST_NOTIFICATIONS` and the channel "Hobs".

**What is covered.** Events only reach the app for Hob chats it has opened
since it started: `AppState` keeps one live `ChatController` per opened Hob
(attached with `session.resume`), and the socket carries events only for those
sessions. A Hob whose chat you haven't opened in this run, or work done in
other sessions (dashboard tabs, cron jobs), does not notify; it still shows as
unread in the list on the next roster refresh.

**iOS background limit.** iOS suspends the app, and with it the WebSocket,
shortly after it leaves the screen. When you background the app while a reply
is still streaming, it asks iOS for a short background task
(`beginBackgroundTask`, channel `hobs/background` in `AppDelegate.swift`) so
the reply can finish and notify; iOS ends that after about 30 seconds. Anything
later (a long turn, an approval asked minutes after you left) arrives only when
you open the app again; then the chat reconnects and shows it. There is no
keep-alive beyond that; reliable notifications in the background would need
real push from the server. Android and macOS keep the socket while the process
lives, though Android may still kill it under battery saving.

## How it talks to Hermes

| Step | Call |
|---|---|
| Login | `POST /auth/password-login` `{provider:"basic",username,password}` → session cookies (`hermes_session_at/rt/provider`). The app stores them and saves every rotated `Set-Cookie`. |
| Hob list | RPC `profiles.list {include_sessions:true}` (REST `GET /api/profiles` as fallback). Folders, title, color, shape and pin come from `ui_meta['hermes-bots']`; preview and time come from `canonical_session`. |
| Chat socket | `POST /api/auth/ws-ticket` (single-use, 30 s) → `wss://…/api/ws?ticket=…`. JSON-RPC 2.0, one object per frame. No `Origin` header is sent. |
| Handshake | the server sends `event gateway.ready`, the client sends `client.capabilities {server_requests:true}`, and the client sends `gateway.ping` every 15 s |
| Hob Chat | Each Hob has one forever-chat: the session titled "Bot Chat". The app opens it with `session.resume` (history included). On a Hob's first chat it calls `session.create {title:"Bot Chat", hidden, follow_profile_config}` followed by `session.title`. |
| Conversation | `prompt.submit {session_id,text}` → events `message.start / message.delta / message.interim / tool.* / message.complete` |
| Mentions | Typing `@` in a chat offers the other Hobs (tag = slug of the title, else the profile name; the default profile is `@hermes`). On send, tagged Hobs add the dashboard's identification note to the prompt text (`[@mentions resolved from the Bot Mode roster — …]`), so the agent can reach them with its `message_agent` tool. The transcript shows the text without the note. |
| Control | `session.interrupt`, `config.set {key:"reasoning", scope:"session"}`, `config.get` / `config.set {key:"approvals.mode", profile}` (profile-wide approval mode: manual, smart, off), server requests `approval` (reply with `{choice}`) and `clarify` (reply with `{answers,outcome}`) |
| Session model | The composer's model chip switches the model of this chat only; the Hob's profile keeps its default. Read: `model.options {profile, session_id}` gives the session's `model`/`provider` (re-read after every `session.resume`, since a lazy snapshot's `info.model` shows the profile's), `model.options {profile}` the Hob's default. Switch: canonical `session.mutate {operation:"model", payload:{model, provider}}`; legacy `config.set {session_id, key:"model", value:"<model> --provider <slug> --session"}`. An expensive model answers `status:"confirmation_required"` with a `confirm` token (canonical, resend it as `payload.confirm`) or `confirm_required` (legacy, resend with `confirm_expensive_model:true`). `status:"deferred"` applies after the running turn. There is no call to drop a session's model, so *Use the Hob's default* switches the session to the default model. |
| Folders | Rename: `profiles.configure {name, ui_meta:{"hermes-bots":{…,sectionName}}, ui_meta_expected_revisions}` for every Hob in the folder (the write replaces the whole `hermes-bots` block, so the app sends it back complete). Folder order is local to the device, like on the dashboard. |
| Hob menu | Long-press a Hob in the list (right-click on macOS): *Pin/Unpin*, *Hide/Show in the list*, *Move to folder* (an existing folder, out of its folder, or a new one by name). Same `profiles.configure` write with the whole block and the dashboard's keys: `pinned` and `hidden` as booleans, `sectionId` + `sectionName` (both `null` to leave a folder; a new folder gets an id like `sec-<base36 time>-<5 chars>`). The list changes at once and goes back with a snackbar if the server refuses; a stale revision is reread and retried once. Pinned Hobs sort first, then by activity, like on the dashboard. Hidden Hobs wait in a closed *Hidden Hobs* group at the end of the list. |
| Hob profile | Tapping the Hob's avatar in the chat header opens its profile. Title, shape and color: `profiles.configure` with the whole `hermes-bots` block, like folders. Description: `cli.exec {argv:["profile","describe",name,"--text",…]}`. Model: `profiles.describe {name}` reads it, `model.options` lists providers, `profiles.configure {name, provider, model}` switches it (`confirm_expensive_model` after the server asks); inheriting again is `cli.exec` `config unset model`. SOUL.md: read from `profiles.describe`, replaced with `profiles.configure {name, soul}`. |
| Attachments | Images: `POST /api/chat/image-upload?profile=<hob>` `{data_url, filename}` → `{path, mime_type}` (the profile's `cache/images/`). Files: multipart `POST /api/chat/file-upload?profile=<hob>` (field `file`) → `{path, staged_upload}`, then right before sending `file.attach {session_id, name, staged_upload}` → `{ref_text:"@file:…"}`. Links: an `@url:<url>` line. The submit text is the ref lines, a blank line, then the message (`What do you see in this image?` for images alone). Canonical gateway: `prompt.submit {…, attachments:[{path, mime}]}`; legacy dispatcher: `image.attach {session_id, path}` before the submit. |
| Attachments in history | User rows carry `@image:<path>`, `@file:<path>`, `@url:<url>` lines (values with spaces quoted in backticks); images are read with `GET /api/fs/download?path=…&profile=<hob>`. |
| Scheduled jobs | `cron.manage {action:"list", profile}` (read-only) |
| Group chats | Rooms of 2–6 Hobs, held by the default profile's gateway; every `groups.*` call carries `profile`. `groups.capabilities` (`driver:true`, `methods`, `seatable_profiles`) decides whether the app offers them. List: `groups.list {limit, offset}` (paged by `next_offset`). Create: `groups.create {room_id:<uuid>, name, members:[{member_id, profile, handle, target:{kind:"local", profile}}]}`. Open: `groups.state {room_id}` (room, `driver_status` with `member_activity` and `pending_actions`) and `groups.log {room_id, since_seq, limit}` (gapless, append-only: `message.user`, `message.member`, `turn.settled/failed/cancelled`, `room.activity`). Send: `groups.send {room_id, event_id, payload:{text, attachments:[], thread_id:event_id}}`; `@handle` at the start assigns the message. The event `groups.changed {room_ids}` triggers a reread; the app also polls (2 s while members work, 15 s otherwise). Control: `groups.stop {room_id, cancel_id}`, `groups.continue {room_id, discussion_event_id}` after a round hit its cap, `groups.approve / retry / discard {room_id, member_id, task_id, execution_generation[, request_id, choice]}`, `groups.rename {room_id, event_id, name}`, `groups.disband {room_id, cancel_id}` (returns a `tombstone`). |
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

The SESSIONS tab, group chats with Hobs of another gateway (peers), routing
settings and attachments in group chats are out of scope. Unread state,
collapsed folders and folder order are stored locally on the device.

## Layout

- `lib/api/hermes_http.dart`: cookie-aware REST client (dart:io)
- `lib/api/hermes_rpc.dart`: `/api/ws` JSON-RPC client (ticket, heartbeat, reconnect, server requests)
- `lib/state/chat_controller.dart`: one conversation, event → message model
- `lib/state/group_chat_controller.dart`: one group chat (room state, log, sending, member status)
- `lib/state/app_state.dart`: login, biometric lock, Hob list, chats per Hob
- `lib/state/biometrics.dart`: `local_auth` wrapper (which biometric, prompt)
- `lib/state/notifications.dart`: local notifications, iOS background time
- `lib/api/attachments.dart`: attachment model, `@image:`/`@file:`/`@url:` refs, turn preparation
- `lib/state/composer_draft.dart`: uploads per Hob (progress, cancel, retry); `image_prep.dart` downscales photos
- `lib/state/share_inbox.dart`: shares from other apps waiting for a Hob
- `lib/ui/`: login, Hob list (split view on wide screens), chat
- `test/`: fake Hermes server covering the whole flow

Web is not a target: browser CORS and cookie rules block cross-origin access to the dashboard.
