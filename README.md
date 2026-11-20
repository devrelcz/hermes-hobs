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
| Control | `session.interrupt`, `config.set {key:"reasoning", scope:"session"}`, `config.get` / `config.set {key:"approvals.mode", profile}` (profile-wide approval mode: manual, smart, off), server requests `approval` (reply with `{choice}`) and `clarify` (reply with `{answers,outcome}`) |
| Folders | Rename: `profiles.configure {name, ui_meta:{"hermes-bots":{…,sectionName}}, ui_meta_expected_revisions}` for every Hob in the folder (the write replaces the whole `hermes-bots` block, so the app sends it back complete). Folder order is local to the device, like on the dashboard. |
| Hob profile | Tapping the Hob's avatar in the chat header opens its profile. Title, shape and color: `profiles.configure` with the whole `hermes-bots` block, like folders. Description: `cli.exec {argv:["profile","describe",name,"--text",…]}`. Model: `profiles.describe {name}` reads it, `model.options` lists providers, `profiles.configure {name, provider, model}` switches it (`confirm_expensive_model` after the server asks); inheriting again is `cli.exec` `config unset model`. SOUL.md: read from `profiles.describe`, replaced with `profiles.configure {name, soul}`. |
| Scheduled jobs | `cron.manage {action:"list", profile}` (read-only) |
| Reconnect | auto backoff, then `session.resume` with the stored id |

The SESSIONS tab and group chats from the dashboard are out of scope. Unread
state, collapsed folders and folder order are stored locally on the device.

## Layout

- `lib/api/hermes_http.dart`: cookie-aware REST client (dart:io)
- `lib/api/hermes_rpc.dart`: `/api/ws` JSON-RPC client (ticket, heartbeat, reconnect, server requests)
- `lib/state/chat_controller.dart`: one conversation, event → message model
- `lib/state/app_state.dart`: login, biometric lock, Hob list, chats per Hob
- `lib/state/biometrics.dart`: `local_auth` wrapper (which biometric, prompt)
- `lib/state/notifications.dart`: local notifications, iOS background time
- `lib/ui/`: login, Hob list (split view on wide screens), chat
- `test/`: fake Hermes server covering the whole flow

Web is not a target: browser CORS and cookie rules block cross-origin access to the dashboard.
