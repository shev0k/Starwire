# Security review: the encrypted microphone on iOS (SWMC, batch 4)

AGENTS.md asks for a review pass and the owner's sign-off for changes to the microphone's
encryption and pairing. This is that review for the iOS app's port of Starwire's encrypted
microphone. The protocol itself is unchanged: [docs/dev/mic-protocol.md](../../dev/mic-protocol.md)
is the contract, and Android and the Windows receiver already implement it.

**Sign-off:** not yet signed. The owner signs by writing their name and the date here.

## What was added

| Piece | Where | What it does |
|---|---|---|
| `SwmcCodec` | `ios/StarwireKit/Sources/StarwireKit/Mic/` | Every message's bytes and every key, ported from Android's `SwmcCodec.java` |
| `PairingCode` | same | The 16-character code: Crockford base32, read the way people type it |
| `MicPairingClient` | same | The pairing exchange: PAIR_REQUEST every 500 ms for 6 s, PAIR_ACCEPT checks, PAIR_REJECT believed only after 500 ms |
| `SwmcSender` | same | Sessions: HELLO timing, HELLO_ACK and REHELLO rules, the counter, sealing each VBAN packet |
| `HomeNetwork` | same | The address filter: private, link-local, loopback and VPN ranges only |
| `VbanPacketizer` | same | 256-sample, 48 kHz mono 16-bit VBAN packets |
| `MicPairingStore` | `ios/Limelight/Starwire/StarwireMicrophone.swift` | One Keychain item per PC |
| `StarwireMicrophone` | same | Capture (AVAudioEngine with voice processing), UDP (Network.framework), statuses |
| `MicPairingScreen` | `ios/Limelight/Starwire/UI/` | Typing the code, showing and removing pairings |

The crypto comes from swift-crypto, which is Apple's CryptoKit on iOS and the same API over
BoringSSL on Windows, so the code the app runs is the code the Windows tests run: HMAC-SHA256,
AES-256-GCM, P-256 key agreement and SHA-256. HKDF is written out in `SwmcCodec.hkdf` so the
"no salt means 32 zero bytes" rule is visible; it passes RFC 5869's test case 1.

## How it was checked

- **The shared vectors.** `MicSwmcTests` reproduces every line of
  `app/src/test/resources/swmc-v1-vectors.txt` (the GCM, HKDF and ECDH known answers from the
  standards, both keys, every packet type, pairing) and checks the file is byte-identical to the
  receiver's copy. 27 tests, passing on Windows and macOS.
- **Against the real receiver.** `ios/scripts/mic-loopback.ps1` builds `StarwireMicReceiver` from
  `windows/` into a temporary folder and starts it on this PC's loopback on port 6995, with its
  own pairings file and no audio output. StarwireKit's `SwmcLoopback` paired with the code it
  printed, started a session and streamed 375 packets in real time. The receiver's summary:
  played 375, the same PCM hash, a replayed packet refused, a plain VBAN packet refused, nothing
  forged, no errors. Run on 25 Oct 2026; no installed receiver was touched.
- **Refusals.** Every flipped bit and every truncation of a HELLO_ACK and an AUDIO packet is
  refused; random junk behind a real header never passes a MAC; a PAIR_ACCEPT with a wrong
  confirmation fails; one made with another code is ignored; points off the curve, compressed
  points, all-zero and all-ones coordinates are refused.
- **The session rules,** with injected time: HELLOs at 0, 250 … 2000 ms then every 2 s; audio
  before the first HELLO_ACK is dropped; a second session for the same HELLO starts a new HELLO
  and never reuses a key from counter 0; a REHELLO only counts for the current session and at
  most every 2 s; the counter starts a new session instead of wrapping.

Not checked: the iPad sending to the PC over Wi-Fi. This PC has no receiver installed, and a
receiver reachable from the iPad needs a Windows Firewall rule, which I didn't create. That is
the hands-on item at the end of the batch.

## Keys and secrets

- **The pairing key** (32 bytes), the device id and the receiver's id are kept per PC in the
  Keychain (service `io.github.shev0k.starwire.mic-pairing`, account = the PC's uuid), with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: not in iCloud Keychain, not restored to
  another device, not readable before the first unlock after a restart. They are never written
  to UserDefaults and never go into the settings JSON export.
- **Session keys** (K_auth, K_audio) live only in memory for the stream.
- **Randomness:** device ids, pairing nonces and client randoms come from
  `SystemRandomNumberGenerator` (the system's cryptographically secure generator); the one-time
  pairing key pair from CryptoKit. Tests inject fixed bytes; the app never does.
- **Nonces never repeat under one key,** by the protocol's design: a new client random from the
  secure generator for every HELLO, at most one session per HELLO, and a counter that only goes
  up and never wraps.
- **Comparisons** of MACs, confirmations, device ids and contexts are constant time.
- **Names** from the PC are cleaned of control and formatting characters before they're shown.

## What it protects against, and what it doesn't

The same as Android, since the protocol is the same: someone on the network can't hear the
microphone, can't inject sound into the PC, and can't replay old audio; a code seen later
(a screenshot) doesn't reveal the pairing key; guessing the code is about 2^80 tries. It doesn't
stop someone flooding or jamming the network, malware on either device, or a stolen iPad that is
still paired (unpair it in the receiver's menu). Packet sizes and timing are visible.

**Addresses are a filter, not the security.** The app only pairs with and sends to home-network
and private VPN addresses. A PC known by a name is looked up first and the filter applies to the
answer. 100.64.0.0/10 is also carrier-grade NAT space, as Android's comment says.

**Plain VBAN** ("Not encrypted" in Settings) is still offered for Voicemeeter and other VBAN
apps, as on Android. It sends the microphone unencrypted to the PC's address on the home
network only.

## iOS-specific points

- The microphone is only captured while a stream runs with "Send my microphone" on, and stops
  with the stream. iOS shows its orange microphone dot while it's captured. iOS asks for the
  microphone permission the first time; the app's text says why
  (`NSMicrophoneUsageDescription`).
- The app keeps the `audio` background mode it had before. In picture in picture the stream, and
  so the microphone, can keep running in the background; the orange dot still shows.
- Capture uses Apple's voice processing (echo and noise cancelling). Whether it cancels the
  stream's own sound well is not measured; that is part of the hands-on item.
- The audio session switches to play-and-record while the microphone is on. The stream's audio
  output handles the route change as it handles any other.

## Questions for the owner

1. Sign off on the iOS port as described: the same protocol, swift-crypto, keys in this device's
   Keychain only.
2. The iPad-to-PC check needs the receiver installed (`windows/setup-microphone.ps1`, which
   installs VB-Cable and adds its firewall rule, and asks for administrator rights). That is
   yours to run; then the hands-on item checks your voice reaches the PC.
