# Google Play release

How the HobCrew app is built, signed and listed on Google Play, and what is
set in Play Console. Package name: `com.hobcrew.app`. The app uses Play App
Signing: Google holds the app signing key, we sign uploads with our own
upload key.

Store page: https://play.google.com/store/apps/details?id=com.hobcrew.app

**Rename, November 24, 2026.** Until then the app was listed as *Hermes Hobs*
(`cz.devrel.hermeshobs`). Hermes Agent is Nous Research's software and their
mark, so the app was renamed HobCrew and gets a new listing under the new
package name; a package name cannot change on Play. HobCrew went live in
production on November 24, 2026, and the old listing was unpublished the
same day. Its state and history are kept below under *Hermes Hobs (old
listing)*.

New listing, November 24, 2026: app HobCrew created in the Daniel Rataj
developer account (free, app, en-US default). Uploads are signed with the
same upload key as Hermes Hobs. Internal testing opt-in link:
https://play.google.com/apps/internaltest/4701499315991673751. Production
needed no closed test first: the account was allowed to release straight to
production.

The HobCrew listing and App content were filled in the same day, mostly with
the answers below (App content answers), with these differences:
- Store settings: category Productivity, contact info@hobcrew.com, website
  https://hobcrew.com.
- Content rating contact: info@hobcrew.com.
- Store listing: en-US, and cs-CZ added later the same day with the Czech
  texts below and `cs/phone-*.png`; `icon-512.png` and `feature-graphic.png`
  are rendered from the new HobCrew mark and labelled as AI-generated assets.
  The phone screenshots are still the Hermes Hobs ones and need retaking.
- Sign in details: the demo instructions use the current button text, "Try
  the demo, no server needed", and the details under "Type the details".
- Data safety: same answers, the outside accounts are described as created
  "By the operator of the user's own Hermes Agent server".

## Current state

| | |
|---|---|
| Published version | 1.0.0 (versionCode 174), production, full rollout, live November 24, 2026 |
| In review | 1.0.1 (versionCode 179), production, full rollout, sent November 24, 2026 |
| Internal testing | 1.0.0 (versionCode 174), tester list *Internal - Home* |
| Production | Full rollout, 178 countries / regions |
| Store listing | English (en-US, default) and Czech (cs-CZ, sent for review November 24, 2026); HobCrew icon and feature graphic shared by both, old Hermes Hobs screenshots per language (`phone-*.png`, `cs/phone-*.png`) |
| Managed publishing | Off: an approved release goes live on its own |

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
Bundle and copies it to `build/hobcrew-<version>-<build>.aab`. The
versionCode is the commit count, so it rises with every commit on master;
the versionName is the `version:` in `pubspec.yaml`. Bump that before a
release users will see.

## Releasing an update

1. Bump `version:` in `pubspec.yaml` (for example `1.0.1+1`; the build number
   after `+` is ignored, the script sets it), commit, merge to master.
2. On master run `tool/build_play.sh`.
3. The bundle is about 70 MB, over the 10 MB browser automation can upload,
   so drag it into Play Console by hand: Test and release > Testing >
   Internal testing > Create new release. Release notes in both languages:

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
| 1.0.0 | 171 | Internal testing | First HobCrew build: new name, package `com.hobcrew.app`, HobCrew icons and colors |
| 1.0.0 | 174 | Production, internal testing | First HobCrew release; the team catalog comes only from the HobCrew API (no jsDelivr fallback) |
| 1.0.1 | 179 | Production (in review) | Released under the Functional Source License (FSL-1.1-ALv2); the app itself is unchanged |
| 1.0.2 | 182 | Production (to upload) | The QR scanner tells HobCrew customers to scan the sign-in code from their crew's page; own-server users scan their server's code |

Release notes for 1.0.2:

```text
<en-US>
The QR scanner now tells you where to find your sign-in code: on your crew's page at HobCrew. If you run your own server, scan its sign-in QR code.
</en-US>
<cs-CZ>
Skener QR kódu teď radí, kde najdete přihlašovací kód: na stránce vaší posádky v HobCrew. Pokud máte vlastní server, naskenujte jeho přihlašovací QR kód.
</cs-CZ>
```

## Hermes Hobs (old listing)

Package `cz.devrel.hermeshobs`, store page
https://play.google.com/store/apps/details?id=cz.devrel.hermeshobs.
Unpublished November 24, 2026 (Advanced settings > App availability): new
users cannot find or install it, existing users keep it and still get
updates. Not deleted. State before the rename:

| | |
|---|---|
| Published version | 1.0.4 (versionCode 145), live November 22, 2026, full rollout; first release was 1.0.0 (versionCode 101), November 2026 |
| In review | 1.0.5 (versionCode 158), production, full rollout, sent November 23, 2026 |
| Store listing | Says the app is unofficial and not from Nous Research (short and full descriptions, en-US and cs-CZ), live November 22, 2026 |
| Production | Full rollout, 178 countries / regions |
| Internal testing | 1.0.0 (versionCode 101), tester list *Internal - Home* |
| Managed publishing | Off: an approved release goes live on its own |
| Listing languages | English (en-US, default) and Czech (cs-CZ) |

Release history:

| Version | versionCode | Track | What changed |
|---|---|---|---|
| 1.0.0 | 101 | Production, internal testing | First release |
| 1.0.1 | 109 | Never uploaded | Built locally only |
| 1.0.2 | 117 | Production | Sign in by scanning the server's QR code; the sign-in screen starts with the choice of scanning or typing the details |
| 1.0.3 | 129 | Production | Settings > About and the licenses page say the app is an unofficial community app, not from Nous Research |
| 1.0.4 | 145 | Production | Manage a Hob's scheduled jobs (switch, run now, history, delete, new job) and show their output as cards in the chat; add another server by scanning its QR code |
| 1.0.5 | 158 | Production | Marketplace with ready-made teams of Hobs (dev, personal, marketing, editorial, startup) added in one tap; duplicate a Hob and see its group chats from the Hob menu; messages between Hobs fold into quiet lines and no longer notify |
| 1.0.6 | 166 | Production (in review) | The Marketplace reads its teams from the HobCrew API (hobcrew.com/api/marketplace/v1/), with jsDelivr as a fallback |

Release notes for 1.0.6:

```text
<en-US>
The Marketplace now loads its ready-made teams from HobCrew, so new teams reach you without an app update.
</en-US>
<cs-CZ>
Marketplace teď načítá hotové týmy z HobCrew, takže nové týmy dostanete bez aktualizace aplikace.
</cs-CZ>
```

Release notes for 1.0.5:

```text
<en-US>
New Marketplace: add a ready-made team of Hobs in one tap, such as a dev team, a personal team or a marketing team. Each Hob gets its role and instructions, and the team gets its own folder and group chat. You can also duplicate a Hob and see its group chats from the Hob menu. Messages between Hobs now show as quiet lines and no longer notify you.
</en-US>
<cs-CZ>
Nový Marketplace: hotový tým Hobíků přidáte jedním klepnutím, třeba vývojový, osobní nebo marketingový. Každý Hobík dostane svou roli a pokyny, tým vlastní složku a skupinový chat. Hobíka teď také zduplikujete a jeho skupinové chaty uvidíte z menu Hobíka. Zprávy mezi Hobíky se zobrazují jako nenápadné řádky a už vás neupozorňují.
</cs-CZ>
```

Release notes for 1.0.4:

```text
<en-US>
Manage each Hob's scheduled jobs from the chat menu: switch them on and off, run one now, see its run history, delete it or schedule a new one. A job's output now shows up in the chat as a card of its own. You can also add another server by scanning its QR code.
</en-US>
<cs-CZ>
Naplánované úlohy Hobíků teď spravujete z menu chatu: zapnete je nebo vypnete, spustíte hned, prohlédnete si historii běhů, smažete je nebo založíte novou. Výstup úlohy se v chatu ukáže jako samostatná karta. Další server navíc přidáte naskenováním jeho QR kódu.
</cs-CZ>
```

Release notes for 1.0.3:

```text
<en-US>
Settings > About now says that Hermes Hobs is an unofficial community app, not made, endorsed or supported by Nous Research.
</en-US>
<cs-CZ>
V Nastavení > O aplikaci teď uvidíte, že Hermes Hobs je neoficiální komunitní aplikace, kterou nevytváří, nepodporuje ani neschvaluje Nous Research.
</cs-CZ>
```

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
developer account's address; website: https://github.com/hobcrew-com/hobcrew-app.

AI asset declaration: *Don't label assets*. The form covers only images, and
the icon, graphic and screenshots are not AI-generated.

The demo (*Try the demo, no server needed* on the sign-in screen,
`lib/demo/`) is how reviewers and people without a server see the app.

Privacy policy URL:
https://github.com/hobcrew-com/hobcrew-app/blob/master/docs/privacy-policy.md

### English (en-US)

App name (30): `HobCrew`

Short description (80):
`Unofficial app for your Hermes Agent bots, here called Hobs. One chat each.`

Full description:

```text
HobCrew is a chat app for your Hermes Agent server. Each bot in Hermes
Bot Mode (a profile on the server) is a Hob here, and every Hob gets its own
chat.

HobCrew is an unofficial community app. It is not made, endorsed or
supported by Nous Research, the makers of Hermes Agent.

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

Název (30): `HobCrew`

Krátký popis (80):
`Neoficiální aplikace pro boty z Hermes Agent. Zde Hobíci, každý má svůj chat.`

Úplný popis:

```text
HobCrew je chatovací aplikace pro váš server Hermes Agent. Každý bot
z Hermes Bot Mode (profil na serveru) je tu Hobík a každý Hobík má vlastní
chat.

HobCrew je neoficiální komunitní aplikace. Nevytváří ji, nepodporuje ani
neschvaluje Nous Research, autoři Hermes Agent.

• Jeden chat na Hobíka. Odpovědi přibývají, jak je Hobík píše, i s nástroji,
  které použil. Příkaz schválíte nebo na otázku odpovíte přímo v chatu.
• Označte další Hobíky. Napište @ a přizvěte do konverzace dalšího Hobíka.
• Skupinové chaty. Zeptejte se 2 až 6 Hobíků najednou a čtěte jejich
  odpovědi v jednom vlákně.
• Seznam podle vás. Složky, připnutí, skrytí Hobíci a filtry nepřečtené,
  připnuté, aktivní a nedávné.
• Profily Hobíků. Změňte Hobíkovi obličej, barvu, titul, popis, model
  a SOUL.md.
• Nastavení chatu. Model, úroveň uvažování a režim schvalování přepnete
  přímo v poli pro psaní.
• Přílohy. Posílejte fotky, soubory do 16 MB a odkazy, nebo je do Hobíka
  sdílejte z jiné aplikace.
• Oznámení, když Hobík dopíše odpověď nebo na vás čeká.
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
