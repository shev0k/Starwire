# Security review: the client identity in the Keychain (iOS, batch 2)

Written 25 Oct 2026 for `feature/ios-batch-2`. AGENTS.md asks for a separate review and the
owner's sign-off for changes to pairing and certificates with the host. This is that review.

**Sign-off:** not yet signed. The owner signs by writing their name and the date here.

## What changed

The client's identity is what the PC pinned when the iPad paired: a self-signed certificate
and its RSA private key. moonlight-ios kept three files in the app's Documents folder:

| File | What it is | Used for |
| --- | --- | --- |
| `client.crt` | the certificate, PEM | sent to the PC when pairing |
| `client.key` | the private key, PEM, not encrypted | signs the pairing secret |
| `client.p12` | both, PKCS #12, passphrase "limelight" (fixed in moonlight-ios) | TLS to the PC's HTTPS port |

Batch 2 moves all three into the Keychain, unchanged:

- `StarwireIdentity.swift` stores each as a generic password item: service
  `io.github.shev0k.starwire.identity`, account the old file name.
- Accessibility `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: readable once the iPad has
  been unlocked after a restart, never in a backup or iCloud Keychain, never on another device.
- `CryptoManager` reads and writes through `StarwireIdentity`, so pairing, TLS and the new Swift
  transport (`PinnedHostTransport`) all use the Keychain copy.
- StarwireKit's `IdentityMigration` copies the files on the first launch, reads every item back,
  and compares the bytes. If the Keychain refuses or gives back anything different, it removes
  what it wrote and the app keeps using the files. Tests cover each case on Windows and on the
  simulator.
- The old files stay until the device run proves the iPad is still paired from the Keychain
  copy. A later commit turns on their removal (`removeFilesAfterMigration`).

## Why the bytes must not change

The PC knows this client only by its certificate (Vibeshine identifies clients by the TLS
certificate alone). A new key or certificate means pairing again, which needs the owner at the
PC. So the migration copies; it never regenerates or re-encodes.

## What it protects against, and what it doesn't

Better than before:
- The private key is no longer a plain file. Before, anything that could read the app's
  Documents folder had it: an unencrypted device backup made by a Mac or PC, and tools like
  `devicectl device copy from` on a development-signed app (batch 2 used exactly this, once, to
  record test answers from the PC; see below).
- `ThisDeviceOnly` keeps the key out of backups and off other devices.

Not changed, and why that's acceptable:
- The PKCS #12 passphrase is still "limelight". It is moonlight-ios's constant and is in public
  source, so it never protected anything; the Keychain item is the protection now. Changing it
  would change the stored bytes for no gain.
- Keychain items outlive the app on iOS: deleting Starwire leaves the identity behind, and a
  reinstall picks it up again (still paired). Apple has not promised this behaviour. The owner's
  rule is to never delete the app anyway.
- The Keychain is tied to the signing team's app identifier prefix. If the app were ever signed
  by a different team (for example the paid work account), it couldn't read the items, and the
  app would make a new identity, so it would need pairing again. The files are kept until this
  batch is proven, which covers the switch while they remain. After they are removed, a team
  change means pairing again.
- A jailbroken or compromised iPad can read Keychain items of a running app. Out of scope.

## Other pairing and certificate changes in this batch

- **Pair-state rules** (StarwireKit `PairStateCheck`, from daniel-zn's Artemis iOS and Starwire for
  Android): a pinned PC that answers only over plain HTTP is not taken as unpaired for 30
  seconds; a paired PC that says over HTTPS that it isn't is asked once more. This only delays
  showing "not paired"; it never trusts a PC more than before. The certificate check is
  unchanged: an HTTPS answer counts as authenticated only when the PC showed the pinned
  certificate.
- **mDNS:** a PC that mDNS finds again at a saved PC's address is now polled over HTTPS with that
  saved PC's pinned certificate. If a different machine answered at that address, its
  certificate wouldn't match, the TLS handshake would fail, and nothing would be taken from it.
- **PinnedHostTransport** (new, Swift) checks the PC's certificate the same way as HttpManager:
  exactly one certificate, byte-equal to the pinned one, or the request is cancelled. It is
  stricter than HttpManager, which falls back to default handling on a mismatch (which then
  fails for a self-signed certificate).
- **Device name:** the pairing requests now send a name (the "Name on the PC" setting, else
  "Starwire on iPad") instead of moonlight-ios's "roth". Vibeshine ignores it at pairing (its
  owner types the name with the PIN); it is also sent as `clientName` at launch.

## The one-off copy of the identity during this batch

To record real answers from the PC for the tests, the agent copied `client.crt` and `client.key`
from the iPad's app container to a private temporary folder on the owner's Mac (mode 700), ran
read-only requests (`/serverinfo`, `/applist`, `/bitrate`, `/power-actions/v1`,
`/api/hardware-metrics`, `/api/abr/capabilities`, and `/launch` and `/resume` without the
parameters they need, which the PC refuses), and deleted the folder when the script ended. The
key never left the Mac or reached git. The recorded files were checked for private values and
redacted before they were committed.

## Questions for the owner

1. Sign off on the Keychain move as described, with the files removed after the device proof.
2. Is keeping "limelight" as the PKCS #12 passphrase acceptable? (Recommended: yes, see above.)
