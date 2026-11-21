# How Hermes Hobs works

Details behind the features in the [README](../README.md): the biometric lock,
notifications, the calls the app makes to Hermes, and attachments.

## Face ID, Touch ID, fingerprint

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

## Notifications

The app fires **local** notifications (`flutter_local_notifications`; no push,
no APNs/FCM, nothing on the server) when:

- a Hob finishes a reply in its Bot Chat (`message.complete`): the Hob's name
  and a short preview;
- a Hob waits for you: an approval (`approval.request` event or `approval`
  server request) or a question (`clarify.request` / `clarify`). The Hob is
  blocked until someone answers, so these matter most;
- a member posts in a group chat: the group's name, then "Hob: preview";
- a group chat waits for you: a member's command to approve or a failed turn
  to retry or drop (`driver_status.pending_actions`).

This covers every visible Hob, not only the chats you opened, and turns that
someone started elsewhere (a dashboard tab, another device) in a Hob's Bot
Chat.

It notifies whenever that chat is not on screen: the app is in the background
(on macOS also when the window is behind other apps), the lock screen is up, or
you are looking at another chat or at the list. One notification per Hob and
one per group; a newer one replaces it and opening the chat clears it.
Replies and prompts that `session.resume` replays after a reconnect don't
notify again (each prompt id / turn notifies once); a prompt that first shows
up in a reconnect snapshot, or a turn that ended with a reply while the socket
was down, does notify. A group notifies each log event at most once: the app
keeps the newest `seq` it looked at per room, so a replayed `groups.log`, a
reconnect or another `groups.changed` repeats nothing. A pending action
notifies once while it stays pending.

Tapping a notification opens that Hob's chat or that group chat (pushed on
phones, beside the list on wide screens). The payload says which: `hob:<name>`
or `group:<room id>` (a bare name from an older version is a Hob). With the
biometric lock on, the lock screen comes first and the chat opens after
unlocking.

The system permission is asked for when you send your first prompt or your
first group message, not at first launch. Settings → Notifications turns them
off (stored in `shared_preferences`, key `notifications`); turning the switch
on asks for the permission again and says so when the system has
notifications blocked. Android 13+ uses `POST_NOTIFICATIONS` and the channel
"Hobs".

**How events reach the app, and what it costs.** The gateway has no
profile-wide subscription: the socket carries a session's events only to
clients that attached it with `session.resume` (`sessions.changed` says only
that something changed, `approval.pending` needs the session). So after
sign-in the app *watches* the Bot Chat of every visible Hob: a listen-only
`ChatController` (`watchOnly`) that attaches the existing Bot Chat with
`session.resume {omit_messages: true}`, so no history crosses the wire, and
skips the model and approval-mode reads a full chat does. Watchers attach one
after another (`_SerialQueue` in `app_state.dart`, also for the re-attach after
a reconnect), never create a Bot Chat, and are dropped for hidden Hobs and when
notifications are off. Opening a watched Hob turns its watcher into the full
chat (history, model, approval mode) and keeps what it already alerted. The
cost is one `session.resume` per Hob at sign-in and after each reconnect, and
one idle attached session per Hob on the server (the server still reads the
transcript's tip from its own database; the gateway re-attaches a live session
alongside other clients instead of taking it over). Hobs without a Bot Chat
have nothing to watch until they get one.

Group chats need no attach: the app already re-reads `groups.list` on every
`groups.changed` and every roster refresh (20 s). A room the app has no open
chat for is *peeked* only when its `latest_seq` grew past what the app looked
at or `groups.changed` named it: one `groups.state` (pending actions) and one
`groups.log {since_seq}` for at most the newest 50 events, one room after
another. A room you opened in this run reports itself through its own
`GroupChatController` instead.

**What is not covered.** Hidden Hobs; sessions other than a Hob's Bot Chat
(dashboard side chats, cron runs, sub-agents); a Hob's prompt or a group's
pending action that was already waiting when the app attached or first saw the
room (the first look only records what is there: it is what you open the app
to, and a cold start would otherwise repeat it every time); a group action
that appears without the room changing (no `groups.changed`, no new log
event) until the room is opened; and everything while iOS keeps the app
suspended (below).

**iOS background limit.** iOS suspends the app, and with it the WebSocket,
shortly after it leaves the screen. When you background the app while a reply
is still streaming (in any chat, a watched Hob or an open group), it asks iOS
for a short background task (`beginBackgroundTask`, channel `hobs/background`
in `AppDelegate.swift`) so the reply can finish and notify; iOS ends that after
about 30 seconds. Anything later (a long turn, an approval asked minutes after
you left) arrives only when you open the app again; then the chats reconnect
and show it. There is no keep-alive beyond that; reliable notifications in the
background would need real push from the server. Android and macOS keep the
socket while the process lives, though Android may still kill it under battery
saving.

## Screens and sheets

What opens over the current screen follows one rule per kind of interaction
(`lib/ui/sheets.dart`, built on Wolt Modal Sheet, which picks the shape from
the window width; wide starts at 700 points):

| Interaction | Phone | Wide window (macOS, tablet) |
|---|---|---|
| Deleting a Hob, disbanding a group, discarding edits, an expensive model | bottom sheet | dialog |
| New Hob | full-screen sheet | large dialog |
| Hob profile, app settings | tall bottom sheet | side sheet from the right |
| Chat settings (model, reasoning, approvals) | bottom sheet from the chip under the composer | dialog |
| Picking a model | bottom sheet with search | dialog with search |
| Hob and folder actions | popover at the finger | popover at the pointer |
| Saved, created, deleted | toast | toast |
| Connection lost in a chat | inline banner above the messages | same |
| Loading the list or a chat | skeleton rows in the content's shape | same |
| Nothing to show (no Hobs, no match, no chat picked) | picture, one line and the action that fixes it | same |
| SOUL.md | full-screen editor from the profile | large dialog |
| New group | full-screen sheet with a grid of faces to pick | large dialog |
| Scheduled jobs | tall bottom sheet of job cards | side sheet |
| Naming (folder, group), adding a link | small text sheet | dialog |
| A Hob asks for approval or a question | card above the composer | same |
| First sign-in on a device | welcome sheet, once | dialog |

In a chat your messages sit on the right, the Hob's answers on the left,
with the day (Today, Yesterday, a weekday, a date) between days. On
phones a Hob row swipes right to pin or unpin and left to hide (with Undo).
Settings end with About: the version, the server and account, and the
licenses, including the bundled Geist typeface.
The question being answered is pinned above the chat only once it scrolls
out of view. On phones a Hob's face flies from the list into the chat's
header; new messages slide in; sending, approving, deleting and moving a
folder give a light haptic tap. All motion stops when the system asks for
reduced motion. Bars that hold text grow with the system text size, and
small grey text keeps at least 4.5:1 contrast in both themes.

Approval cards show the command as code with a copy button; Deny and
Allow once are the main pair, other choices sit quieter below. Images in a
message form a grid (one large, rows of tiles, "+N" past six) and open a
swipeable gallery; files and links are cards with their type. On desktops
⌘N (Ctrl+N) starts a new Hob, ⌘K jumps into search, ⌘, opens settings, and
the line between the list and a chat drags to resize the list (kept per
device).

Errors stay plain snackbars. Text is set in Geist, code and SOUL.md in Geist Mono, both bundled under `assets/fonts` (SIL Open Font License). Sheets that hold unsaved work (New Hob, the
profile) close only through their own close button, never by a tap beside
them or a drag.

## How it talks to Hermes

| Step | Call |
|---|---|
| Login | `POST /auth/password-login` `{provider:"basic",username,password}` → session cookies (`hermes_session_at/rt/provider`). The app stores them and saves every rotated `Set-Cookie`. |
| Hob list | RPC `profiles.list {include_sessions:true}` (REST `GET /api/profiles` as fallback). Folders, title, color, shape and pin come from `ui_meta['hermes-bots']`; preview and time come from `canonical_session`. |
| Chat socket | `POST /api/auth/ws-ticket` (single-use, 30 s) → `wss://…/api/ws?ticket=…`. JSON-RPC 2.0, one object per frame. No `Origin` header is sent. |
| Handshake | the server sends `event gateway.ready`, the client sends `client.capabilities {server_requests:true}`, and the client sends `gateway.ping` every 15 s |
| Hob Chat | Each Hob has one forever-chat: the session titled "Bot Chat". The app opens it with `session.resume` (history included). On a Hob's first chat it calls `session.create {title:"Bot Chat", hidden, follow_profile_config}` followed by `session.title`. Hobs whose chat is not open are watched for notifications with `session.resume {omit_messages:true}` (no history; see Notifications). |
| Conversation | `prompt.submit {session_id,text}` → events `message.start / message.delta / message.interim / tool.* / message.complete` |
| Mentions | Typing `@` in a chat offers the other Hobs (tag = slug of the title, else the profile name; the default profile is `@hermes`). On send, tagged Hobs add the dashboard's identification note to the prompt text (`[@mentions resolved from the Bot Mode roster — …]`), so the agent can reach them with its `message_agent` tool. The transcript shows the text without the note. |
| Control | `session.interrupt`, `config.set {key:"reasoning", scope:"session"}`, `config.get` / `config.set {key:"approvals.mode", profile}` (profile-wide approval mode: manual, smart, off), server requests `approval` (reply with `{choice}`) and `clarify` (reply with `{answers,outcome}`) |
| Session model | The composer's model chip switches the model of this chat only; the Hob's profile keeps its default. Read: `model.options {profile, session_id}` gives the session's `model`/`provider` (re-read after every `session.resume`, since a lazy snapshot's `info.model` shows the profile's), `model.options {profile}` the Hob's default. Switch: canonical `session.mutate {operation:"model", payload:{model, provider}}`; legacy `config.set {session_id, key:"model", value:"<model> --provider <slug> --session"}`. An expensive model answers `status:"confirmation_required"` with a `confirm` token (canonical, resend it as `payload.confirm`) or `confirm_required` (legacy, resend with `confirm_expensive_model:true`). `status:"deferred"` applies after the running turn. There is no call to drop a session's model, so *Use the Hob's default* switches the session to the default model. |
| Folders | Rename: `profiles.configure {name, ui_meta:{"hermes-bots":{…,sectionName}}, ui_meta_expected_revisions}` for every Hob in the folder (the write replaces the whole `hermes-bots` block, so the app sends it back complete). Folder order is local to the device, like on the dashboard. |
| Hob menu | Long-press a Hob in the list (right-click on macOS) opens a popover at the finger or pointer: *Pin/Unpin*, *Hide/Show in the list*, *Move to folder* (an existing folder, out of its folder, or a new one by name), *Delete*. Same `profiles.configure` write with the whole block and the dashboard's keys: `pinned` and `hidden` as booleans, `sectionId` + `sectionName` (both `null` to leave a folder; a new folder gets an id like `sec-<base36 time>-<5 chars>`). The list changes at once and goes back with a snackbar if the server refuses; a stale revision is reread and retried once. Pinned Hobs sort first, then by activity, like on the dashboard. Hidden Hobs wait in a closed *Hidden Hobs* group at the end of the list. |
| Delete Hob | *Delete* in the Hob menu asks in a bottom sheet (a dialog on wide screens), then `DELETE /api/profiles/<name>` like the dashboard: the server stops the profile's gateway and removes it with its config, memory, skills and conversations. The Hob leaves the list at once and its chat closes; a refusal keeps it and says why in a snackbar. |
| Hob profile | Tapping the Hob's avatar in the chat header opens its profile as a side sheet (a tall bottom sheet on phones); it closes only through its close button, which asks about unsaved edits. The model is one field that opens a searchable list of every model of the signed-in providers. Title, shape and color: `profiles.configure` with the whole `hermes-bots` block, like folders. Description: `cli.exec {argv:["profile","describe",name,"--text",…]}`. Model: `profiles.describe {name}` reads it, `model.options` lists providers, `profiles.configure {name, provider, model}` switches it (`confirm_expensive_model` after the server asks); inheriting again is `cli.exec` `config unset model`. SOUL.md: read from `profiles.describe`, replaced with `profiles.configure {name, soul}`. |
| New Hob | The "+" above the list opens *Nový Hobík* as a full-screen sheet, a large dialog on wide screens (a menu offers it next to a new group chat when the server has them): name, handle (`@…`, the profile name; made from the name without accents, with `-2`, `-3`… added when a Hob already has it and `hob` when nothing usable is left; shown under the name; tapping it opens the handle field, and the typed one is checked against the server rule `^[a-z0-9][a-z0-9_-]{0,63}$` and the roster), description and a blobatar face. `profiles.create {name, description, clone_from:"default", share_auth:true, soul}` like the dashboard's New Bot dialog (the SOUL.md names its role and mission; the server injects the messaging protocol), then `profiles.configure {name, ui_meta:{"hermes-bots":{shape, imageKind:"shape", title, created}}}` (best-effort). Closing a filled sheet asks before throwing it away. The new Hob's chat opens right after. |
| Attachments | Images: `POST /api/chat/image-upload?profile=<hob>` `{data_url, filename}` → `{path, mime_type}` (the profile's `cache/images/`). Files: multipart `POST /api/chat/file-upload?profile=<hob>` (field `file`) → `{path, staged_upload}`, then right before sending `file.attach {session_id, name, staged_upload}` → `{ref_text:"@file:…"}`. Links: an `@url:<url>` line. The submit text is the ref lines, a blank line, then the message (`What do you see in this image?` for images alone). Canonical gateway: `prompt.submit {…, attachments:[{path, mime}]}`; legacy dispatcher: `image.attach {session_id, path}` before the submit. |
| Attachments in history | User rows carry `@image:<path>`, `@file:<path>`, `@url:<url>` lines (values with spaces quoted in backticks); images are read with `GET /api/fs/download?path=…&profile=<hob>`. |
| Scheduled jobs | `cron.manage {action:"list", profile}` (read-only) |
| Group chats | Rooms of 2–6 Hobs, held by the default profile's gateway; every `groups.*` call carries `profile`. `groups.capabilities` (`driver:true`, `methods`, `seatable_profiles`) decides whether the app offers them. List: `groups.list {limit, offset}` (paged by `next_offset`). Create: `groups.create {room_id:<uuid>, name, members:[{member_id, profile, handle, target:{kind:"local", profile}}]}`. Open: `groups.state {room_id}` (room, `driver_status` with `member_activity` and `pending_actions`) and `groups.log {room_id, since_seq, limit}` (gapless, append-only: `message.user`, `message.member`, `turn.settled/failed/cancelled`, `room.activity`). Send: `groups.send {room_id, event_id, payload:{text, attachments:[], thread_id:event_id}}`; `@handle` at the start assigns the message. The event `groups.changed {room_ids}` triggers a reread; the app also polls (2 s while members work, 15 s otherwise). Control: `groups.stop {room_id, cancel_id}`, `groups.continue {room_id, discussion_event_id}` after a round hit its cap, `groups.approve / retry / discard {room_id, member_id, task_id, execution_generation[, request_id, choice]}`, `groups.rename {room_id, event_id, name}`, `groups.disband {room_id, cancel_id}` (returns a `tombstone`). |
| Reconnect | auto backoff, then `session.resume` with the stored id |

## Attachments and sharing

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
