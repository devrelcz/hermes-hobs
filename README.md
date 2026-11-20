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
| Session model | The composer's model chip switches the model of this chat only; the Hob's profile keeps its default. Read: `model.options {profile, session_id}` gives the session's `model`/`provider` (re-read after every `session.resume`, since a lazy snapshot's `info.model` shows the profile's), `model.options {profile}` the Hob's default. Switch: canonical `session.mutate {operation:"model", payload:{model, provider}}`; legacy `config.set {session_id, key:"model", value:"<model> --provider <slug> --session"}`. An expensive model answers `status:"confirmation_required"` with a `confirm` token (canonical, resend it as `payload.confirm`) or `confirm_required` (legacy, resend with `confirm_expensive_model:true`). `status:"deferred"` applies after the running turn. There is no call to drop a session's model, so *Use the Hob's default* switches the session to the default model. |
| Folders | Rename: `profiles.configure {name, ui_meta:{"hermes-bots":{…,sectionName}}, ui_meta_expected_revisions}` for every Hob in the folder (the write replaces the whole `hermes-bots` block, so the app sends it back complete). Folder order is local to the device, like on the dashboard. |
| Hob profile | Tapping the Hob's avatar in the chat header opens its profile. Title, shape and color: `profiles.configure` with the whole `hermes-bots` block, like folders. Description: `cli.exec {argv:["profile","describe",name,"--text",…]}`. Model: `profiles.describe {name}` reads it, `model.options` lists providers, `profiles.configure {name, provider, model}` switches it (`confirm_expensive_model` after the server asks); inheriting again is `cli.exec` `config unset model`. SOUL.md: read from `profiles.describe`, replaced with `profiles.configure {name, soul}`. |
| Scheduled jobs | `cron.manage {action:"list", profile}` (read-only) |
| Group chats | Rooms of 2–6 Hobs, held by the default profile's gateway; every `groups.*` call carries `profile`. `groups.capabilities` (`driver:true`, `methods`, `seatable_profiles`) decides whether the app offers them. List: `groups.list {limit, offset}` (paged by `next_offset`). Create: `groups.create {room_id:<uuid>, name, members:[{member_id, profile, handle, target:{kind:"local", profile}}]}`. Open: `groups.state {room_id}` (room, `driver_status` with `member_activity` and `pending_actions`) and `groups.log {room_id, since_seq, limit}` (gapless, append-only: `message.user`, `message.member`, `turn.settled/failed/cancelled`, `room.activity`). Send: `groups.send {room_id, event_id, payload:{text, attachments:[], thread_id:event_id}}`; `@handle` at the start assigns the message. The event `groups.changed {room_ids}` triggers a reread; the app also polls (2 s while members work, 15 s otherwise). Control: `groups.stop {room_id, cancel_id}`, `groups.continue {room_id, discussion_event_id}` after a round hit its cap, `groups.approve / retry / discard {room_id, member_id, task_id, execution_generation[, request_id, choice]}`, `groups.rename {room_id, event_id, name}`, `groups.disband {room_id, cancel_id}` (returns a `tombstone`). |
| Reconnect | auto backoff, then `session.resume` with the stored id |

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
- `lib/ui/`: login, Hob list (split view on wide screens), chat
- `test/`: fake Hermes server covering the whole flow

Web is not a target: browser CORS and cookie rules block cross-origin access to the dashboard.
