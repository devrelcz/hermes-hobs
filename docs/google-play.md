# Google Play release

How Hermes Hobs is built, signed and listed on Google Play. Package name:
`cz.devrel.hermeshobs`. The app uses Play App Signing: Google holds the app
signing key, we sign uploads with our own upload key.

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

## Releasing

1. Build on master and upload the `.aab` to a track in Play Console
   (Test and release > Testing > Internal testing, or Production).
2. Release notes: what changed, in Czech and English.
3. Promote the same release from internal testing to closed testing or
   production once it is checked.

A personal developer account created after November 2023 must run a closed
test with at least 12 testers for 14 days before it can apply for
production access.

## Store listing

Assets are in `docs/play/`: `icon-512.png`, `feature-graphic.png`
(source `feature-graphic.svg`), and phone screenshots `phone-*.png` (the
README screenshots padded to 600x1200 so they fit Play's 2:1 limit; they show
the iOS status bar, so replace them with Android captures when there is
time).

Category: Productivity. Contact email: the developer account's address.
Privacy policy URL:
https://github.com/danielrataj/hermes-hobs/blob/master/docs/privacy-policy.md

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

Answers for Policy > App content. Check them against the current Play forms
before submitting; the forms change.

- **Privacy policy**: URL above.
- **Ads**: No ads.
- **App access**: All functionality needs a login to the user's own Hermes
  server. Give reviewers a reachable test server with a username and
  password, or the app cannot be reviewed.
- **Content rating** (IARC questionnaire): category "Communication" style
  app; users can exchange content with an AI agent on their own server; no
  violence, sexual content, gambling or purchases. Users interact with
  generated content, so answer yes to user-generated / shared content where
  asked.
- **Target audience**: 18 and over.
- **News app**: No.
- **Government app**: No.
- **Financial features**: None.
- **Health**: None.
- **Data safety**:
  - The app sends messages, photos, files and the username to a server the
    user chooses, not to the developer. Play counts any transmission off the
    device as collection, so declare: Messages (other in-app messages),
    Photos, Files and docs, Personal info > User IDs. Purpose: App
    functionality. Not shared with third parties. Collection is required to
    use the app.
  - Encrypted in transit: Yes (release builds only allow HTTPS).
  - Data deletion: users remove an account in Settings > Accounts, which
    deletes its data from the device; messages on the server are deleted by
    the server's operator.
