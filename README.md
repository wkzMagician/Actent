# Actent

Actent is a cross-device programmable content router:

```text
Android Share -> ActentMessage -> Work Picker -> LAN-first encrypted Packet
               -> remote Work queue -> WorkReceipt -> optional Android Share
```

Business code is under `lib/features`. The generic messaging and pairing
capabilities are implemented in the local package skeletons:

- `packages/dartloom_messaging`: Packet schema/validation, X25519 + HKDF +
  AES-GCM, LAN/TLS framing, ntfy relay, retry, deduplication and authenticated
  attachment chunks.
- `packages/dartloom_pairing`: invite URI, short-code confirmation, relay
  control handshake, temporary TLS pairing, mDNS discovery and QR contracts.

The Actent layer only owns `ActentMessage`, Work, Catalog, Inbox, persistence
and UI. Private keys, relay authorization and secret Work environment values
are kept in Dartloom Secure Settings; normal messages and attachments use the
application-private JSON/file store without extra static encryption.
The versioned message contract is published at
`schemas/actent_message.schema.json` (schema version 1).

## Development

```text
dart format .
flutter analyze
flutter test

cd packages/dartloom_messaging
dart analyze lib --fatal-infos
dart test -j 1

cd ../dartloom_pairing
dart analyze lib --fatal-infos
dart test -j 1
```

Supported project targets are Android, Windows and Linux. Windows builds use
`tool/build_windows.ps1`; Linux builds use `tool/build_linux.ps1`. These scripts
provide `RESIDENT_ICON_PATH` for the resident/tray capability. Linux builds
must run on a Linux host.

Android instrumentation tests are under
`android/app/src/androidTest` and require an attached emulator or device.

## Android Share

The Android manifest declares `ACTION_SEND` and `ACTION_SEND_MULTIPLE`. Incoming
`content://` attachments are copied into Actent's private attachment directory
before a versioned `ActentMessage` is emitted. FileProvider grants temporary
read-only `content://` URIs when an Android Intent Work runs.

## Relay and LAN pairing

The default relay is `https://ntfy.sh`; the Settings page can save a custom
server URL and authorization value in Secure Settings. Restart Actent after a
change to reconnect the subscription.

LAN packet delivery and temporary LAN pairing are enabled only when a TLS
certificate and private key are provided. Windows/Linux startup also needs the
resident icon define; the helper scripts add it automatically:

```text
.\tool\run_windows.ps1 -FlutterArgs '--dart-define=ACTENT_LAN_CERT_PATH=C:/path/actent.crt' '--dart-define=ACTENT_LAN_KEY_PATH=C:/path/actent.key' '--dart-define=ACTENT_LAN_HOST=192.168.1.20'
```

Without these defines the app remains relay-only. When configured, opening
“Pair device” publishes a short-lived DNS-SD/mDNS advertisement. The Devices
page can discover it, fetch the temporary invite over TLS, verify the issuer
public-key fingerprint and certificate pin, then complete the proof/short-code
handshake before saving an endpoint.

The upstream Dartloom registry currently does not yet contain
`messaging.default` or `pairing.default`; generated files under
`lib/capabilities` are intentionally left untouched until those upstream
registrations are available.
