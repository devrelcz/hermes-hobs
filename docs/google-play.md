# Google Play release

How Hermes Hobs is built, signed and listed on Google Play, and what is set
in Play Console. Package name: `cz.devrel.hermeshobs`. The app uses Play App
Signing: Google holds the app signing key, we sign uploads with our own
upload key.

Store page: https://play.google.com/store/apps/details?id=cz.devrel.hermeshobs

## Current state

| | |
|---|---|
| Published version | 1.0.0 (versionCode 101), first release, November 2026 |
| In review | 1.0.2 (versionCode 117), sent November 22, 2026, full rollout to production |
| Production | Full rollout, 178 countries / regions |
| Internal testing | 1.0.0 (versionCode 101), tester list *Internal - Home* |
| Managed publishing | Off: an approved release goes live on its own |
| Listing languages | English (en-US, default) and Czech (cs-CZ) |

## Upload key

`android/key.properties` (gitignored) points Gradle at the upload keystore:

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/Users/<you>/upload-keystore-hermeshobs.jks
```

Keep the keystore and its password in a password manager. If the upload key
is lost, the account owner can ask Google to reset it in Play Console
(Test and release > App integrity > Upload key certificate), so a lost key
costs a few days, not the app.

Without `key.properties`, release builds are signed with the debug key, which
is enough for `tool/install_android.sh` but rejected by Play.

## Build

```bash
tool/build_play.sh
```

The script refuses to run with uncommitted changes, builds a signed App
Bundle and copies it to `build/hermes-hobs-<version>-<build>.aab`. The
versionCode is the commit count, so it rises with every commit on master;
the versionName is the `version:` in `pubspec.yaml`. Bump that before a
release users will see.

## Releasing an update

1. Bump `version:` in `pubspec.yaml` (for example `1.0.1+1`; the build number
   after `+` is ignored, the script sets it), commit, merge to master.
2. On master run `tool/build_play.sh`.
3. The bundle is about 60 MB, too big for browser automation, so drag it
   into Play Console by hand: Test and release > Testing > Internal testing >
   Create new release. Release notes in both languages:

   ```text
   <en-US>
   ...
   </en-US>
   <cs-CZ>
   ...
   </cs-CZ>
   ```

   The notes field starts with an `en-US` placeholder block; replace all of
   it, or Play reports a tag error.
4. Save and publish: internal testers get it within minutes, without review.
5. Production > Create new release > Add from library, pick the same
   versionCode, the same notes, Save. Then Publishing overview > Send changes
   for review. Reviews usually take up to 7 days; sending new changes while
   one is running restarts it.

This account already had production access, so no closed test with 12
testers was needed.

Production can also take a new bundle directly (Production > Create new
release, upload there), skipping internal testing; 1.0.2 went that way.

## Release history

| Version | versionCode | Track | What changed |
|---|---|---|---|
| 1.0.0 | 101 | Production, internal testing | First release |
| 1.0.1 | 109 | Never uploaded | Built locally only |
| 1.0.2 | 117 | Production (in review) | Sign in by scanning the server's QR code; the sign-in screen starts with the choice of scanning or typing the details |

Release notes for 1.0.2:

```text
<en-US>
Sign in by scanning your server's QR code: run ./pair.sh on a hermes-box server and point the camera at it. No more typing long passwords on your phone. The sign-in screen is simpler too.
</en-US>
<cs-CZ>
Přihlášení naskenováním QR kódu serveru: na serveru hermes-box spusťte ./pair.sh a namiřte na kód fotoaparát. Dlouhé heslo už v telefonu psát nemusíte. Přihlašovací obrazovka je navíc přehlednější.
</cs-CZ>
```

1.0.2 adds the camera (CAMERA permission, the bundled ML Kit barcode reader).
Play warned that the download grows noticeably; no device lost support.

## Store listing

Assets are in `docs/play/`: `icon-512.png`, `feature-graphic.png`
(source `feature-graphic.svg`), and phone screenshots: `phone-*.png` for the
English listing and `cs/phone-*.png` for the Czech one. They are captures of
the demo (*Try the demo*) on an Android phone in dark mode, with the app
language set in Settings. To redo them: `adb exec-out screencap -p`, then cut
the status and navigation bars to 1080x2160, then widen to 1215x2160 by
repeating the edge pixels (Play wants 9:16). On Samsung phones, also paint
over the Edge panel handle on the right.
The demo Hobs and chats are in English in both sets.

Store settings: app, free, category Productivity. Contact email: the
developer account's address; website: https://github.com/devrelcz/hermes-hobs.

AI asset declaration: *Don't label assets*. The form covers only images, and
the icon, graphic and screenshots are not AI-generated.

The demo (*Try the demo, no server needed* on the sign-in screen,
`lib/demo/`) is how reviewers and people without a server see the app.

Privacy policy URL:
https://github.com/devrelcz/hermes-hobs/blob/master/docs/privacy-policy.md

### English (en-US)

App name (30): `Hermes Hobs`

Short description (80):
`Chat with the Hobs on your Hermes Agent server, one chat per Hob.`

Full description:

```text
Hermes Hobs is a chat app for your Hermes Agent server. Each profile on the
server is a Hob, and every Hob gets its own chat.

• One chat per Hob. Replies stream in as the Hob writes them, with the tools
  it used. Approve a command or answer a question right in the chat.
• Tag other Hobs. Type @ to pull another Hob into the conversation.
• Group chats. Ask 2 to 6 Hobs at once and read their answers in one thread.
• Your list, your way. Folders, pins, hidden Hobs, and filters for unread,
  pinned, active and recent.
• Hob profiles. Change a Hob's face, color, title, description, model and
  SOUL.md.
• Per-chat settings. Switch the model, reasoning level and approval mode
  from the composer.
• Attachments. Send photos, files up to 16 MB and links, or share them into
  a Hob from any other app.
• Notifications when a Hob finishes a reply or waits for you.
• More than one server. Each Hermes server is an account you can switch to.
• Fingerprint or face unlock locks the app when you leave it.

You need a Hermes Agent dashboard reachable over HTTPS and an account on it.
The app talks only to the servers you add; it has no analytics and sends
nothing to the developer.
```

### Czech (cs-CZ)

Název (30): `Hermes Hobs`

Krátký popis (80):
`Chatujte s Hoby na svém serveru Hermes Agent, každý Hob má vlastní chat.`

Úplný popis:

```text
Hermes Hobs je chatovací aplikace pro váš server Hermes Agent. Každý profil
na serveru je Hob a každý Hob má vlastní chat.

• Jeden chat na Hoba. Odpovědi přibývají, jak je Hob píše, i s nástroji,
  které použil. Příkaz schválíte nebo na otázku odpovíte přímo v chatu.
• Označte další Hoby. Napište @ a přizvěte do konverzace dalšího Hoba.
• Skupinové chaty. Zeptejte se 2 až 6 Hobů najednou a čtěte jejich odpovědi
  v jednom vlákně.
• Seznam podle vás. Složky, připnutí, skrytí Hobové a filtry nepřečtené,
  připnuté, aktivní a nedávné.
• Profily Hobů. Změňte Hobovi obličej, barvu, titul, popis, model a SOUL.md.
• Nastavení chatu. Model, úroveň uvažování a režim schvalování přepnete
  přímo v poli pro psaní.
• Přílohy. Posílejte fotky, soubory do 16 MB a odkazy, nebo je do Hoba
  sdílejte z jiné aplikace.
• Oznámení, když Hob dopíše odpověď nebo na vás čeká.
• Víc serverů. Každý server Hermes je účet, mezi kterými přepínáte.
• Otisk prstu nebo odemknutí obličejem zamkne aplikaci, když ji opustíte.

Potřebujete dashboard Hermes Agent dostupný přes HTTPS a účet na něm.
Aplikace komunikuje jen se servery, které přidáte, nemá analytiku a vývojáři
nic neposílá.
```

## App content answers

What is filed under Policy and programs > App content. Keep it in step with
the app: a change in what data the app sends, or in how reviewers get in,
means updating the form and sending it for review.

- **Privacy policy**: URL above.
- **Ads**: No ads. **Advertising ID**: not used.
- **Sign in details** (formerly App access): *Yes, part of the app is
  restricted*, with one entry, "Built-in demo (no account needed)", no
  username or password, these instructions, and "full access" ticked:
  "No username or password is needed. On the sign-in screen tap "Try the
  demo" (Czech: "Vyzkoušet demo"). It runs a sample Hermes server inside the
  app with demo Hobs, chats and a group chat; no account or network server is
  needed, and every feature can be reviewed there. Real use needs the user's
  own Hermes Agent server, entered in the Server field."
  Since 1.0.2 the button reads "Try the demo, no server needed" ("Vyzkoušet
  demo bez serveru") and the server details are behind "Type the details";
  the filed text still matches closely enough, so it was left as it is.
- **Content rating** (IARC): category *All Other App Types*. Online content
  (AI-generated content from the user's server): Yes. Everything else No:
  ratings-relevant content in the package, sharing content with other users,
  violence, sexuality, language, controlled substances, age-restricted
  products, sharing location, digital purchases, cash rewards, browser or
  search engine, news or education. Result: PEGI 3, ESRB Everyone, USK 0,
  IARC 3+.
- **Target audience**: 18 and over.
- **Government app, financial features, health**: none.
- **Data safety**:
  - Collected (sent to the server the user chooses; Play counts any
    transmission off the device), none shared with third parties:

    | Data type | Required | Purpose |
    |---|---|---|
    | Personal info > User IDs | Yes | App functionality, Account management |
    | Messages > Other in-app messages | Yes | App functionality |
    | Photos and videos > Photos | No, users choose | App functionality |
    | Files and docs | No, users choose | App functionality |

    None is processed ephemerally: the Hermes server keeps it.
    The QR scanner (1.0.2) reads camera frames on the device and keeps none,
    so it adds nothing here.
  - Encrypted in transit: No. The app connects to the address the user
    enters, which may be `http://` (Dart's HTTP client ignores Android's
    cleartext block); it is encrypted only on `https://`.
  - Accounts: the app does not create accounts. Users sign in with accounts
    created outside the app, "Other": by the operator of their own Hermes
    Agent server.
  - Data deletion request (optional question): not answered. The developer
    holds no user data; removing an account in Settings > Accounts deletes
    its data from the device, and messages on the server are deleted by the
    server's operator.
