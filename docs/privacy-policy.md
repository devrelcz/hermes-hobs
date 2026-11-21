# Hermes Hobs privacy policy

Last updated: 21 November 2026

Hermes Hobs is a chat app for a Hermes Agent server that you run or have
access to. This policy explains what the app does with your data.

## Who receives your data

The app talks only to the Hermes servers you add to it. The developer of
Hermes Hobs runs no server for the app and receives none of your data. The
app has no analytics, advertising or crash-reporting SDKs.

What you send in a chat (messages, photos, files, links) goes to the Hermes
server you are signed in to, and that server's operator decides how it is
stored and used. If you run the server yourself, that is you.

The demo (*Try the demo* on the sign-in screen) runs a stand-in server inside
the app, on the device itself. What you type in the demo stays on the device
and is gone when the app restarts.

## What is stored on your device

- For each server account: its address, your username, a name and color you
  pick, your password and the session cookies. The password and cookies are
  kept in the Android Keystore (iOS/macOS Keychain); the rest in the app's
  private preferences.
- App settings and local bookkeeping such as folders, pins and read markers.

Removing an account in Settings > Accounts deletes its password, cookies and
local bookkeeping from the device. Uninstalling the app deletes everything it
stored on the device.

## Permissions

- **Internet**: to reach your Hermes servers, at the address you enter. Use an
  `https://` address so the connection is encrypted.
- **Notifications**: local notifications when a Hob finishes a reply or waits
  for you. They are created on the device; no push service is used.
- **Biometrics**: the optional app lock uses the system's Face ID, Touch ID or
  fingerprint prompt. The app never sees your biometric data.
- **Photos and files**: only the items you pick or share into the app, and
  only to send them to your Hermes server.

## Children

The app is not directed at children.

## Changes and contact

Changes to this policy are published in this file, in the app's public
repository: https://github.com/danielrataj/hermes-hobs. Questions go to the
repository's issue tracker.
