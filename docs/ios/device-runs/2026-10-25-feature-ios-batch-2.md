# Device run: feature/ios-batch-2, 2026-10-25

Batch 2 is phases 1b and 2 of [the plan](../port-plan.md): the Swift seams, the settings store,
the pairing rules, the client identity in the Keychain, and Vibeshine's launch options and
endpoints. Every build, install and test was started from the Windows PC with
`ios/scripts/mac.sh`, with nobody at the Mac or the iPad.

## What was run

| | |
| --- | --- |
| Date and time (UTC) | 25 Oct 2026, about 06:25 to 06:50 |
| Branch and commit | `feature/ios-batch-2`, `864935c7` plus the test fixes in `96be7b34`, then `1dc601d1` for the file removal |
| Who ran it | Claude Code on the Windows PC, through `mac.sh` |
| Mac | MacBook Air (M1, 2020), macOS 27.0.1, Xcode 27.0 |
| iPad | iPad Pro 11-inch (M4), iPadOS 27.0.1 |
| Bundle ID and signing | `io.github.shev0k.starwire`, the same free personal team |
| Build configuration | Release on the iPad; Debug, signed ad hoc, for the simulator tests |
| PC and host | Vibeshine 2.0.1, RTX 5090. The "Starwire test pattern" app on its own virtual display |
| Network | iPad on Wi-Fi, PC wired, as in batch 1 |

## Tests

| Test | Result | Notes |
| --- | --- | --- |
| `swift test` for StarwireKit | 90 passed | On the Windows PC (`ios/scripts/swift-test.ps1`); CI runs it on macOS |
| Unit tests on the simulator | 129 passed | Includes the Keychain store, the migration, the pair-state rules and the launch request |
| Device-run tests on the iPad | passed, except Remote Monitor | See below |

## The client identity in the Keychain

| Step | Result |
| --- | --- |
| Before: the identity in Documents | `client.crt`, `client.key` and `client.p12` there, unchanged since the iPad paired |
| First batch 2 build installed over the old copy | The app's log: `Client identity: migrated(filesRemoved: false)` |
| Still paired, from the Keychain copy | A stream at 2420x1668 and 120 FPS started at once; HTTPS to the PC needs the client certificate, which the app now reads from the Keychain |
| Build that removes the files | `alreadyInKeychain(filesRemoved: true)`; Documents then held only the database |
| Still paired, Keychain only | `testStreamsInARow` with 3 streams passed |
| Reinstalled over the top again | `alreadyInKeychain`, then a 30 second stream: 120 FPS, 0.00% drops |

The owner didn't have to pair again at any point. The security review is
[security/2026-10-25-keychain-identity.md](../security/2026-10-25-keychain-identity.md).

## Vibeshine features

| Feature | Result |
| --- | --- |
| Virtual display at 2420x1668, 120 Hz | `virtualDisplay=1`: the PC made a 2420x1668 virtual display. 60 s at 120.2 FPS, AV1 10-bit HDR, 0.03% drops, decode about 2.9 ms |
| Scale factor | `scaleFactor=150`: the PC's log said "Using launch resolution override 3630x2502 for client scaleFactor=150". The stream stayed 2420x1668 |
| Exact frame rate | `mode=2420x1668x119.88` was sent. The PC's log only said "display refresh 120 Hz", so 119.88 Hz isn't confirmed |
| VRR request | `clientVrrRequested=1`: the PC's log said "Client requested VRR low-latency stream policy", made the virtual display 1000 Hz and set its frame limiter to 120. The test pattern (a browser page) ran unevenly at first: 74.6 FPS in the first sample, then 120 FPS |
| Bitrate during a stream | From the button in the stream's corner. Before: 87.9 Mbps. After asking for 20: the PC applied 20 and the stream measured 12.0 Mbps. After 70: applied 70, 41.5 Mbps (the page doesn't need more). No drops |
| Remote Input tile | Started at once next to the running game and connected; it sends no picture, as Vibeshine documents |
| Remote Monitor tile | **Failed on the PC.** Vibeshine answered "The owned virtual display could not be created or reclaimed" while the test pattern ran, and after quitting it "The composed display topology did not apply". Its log shows Windows refusing the display change (`SetDisplayConfig`: "A device attached to the system is not functioning"). The app sent the launch and showed the PC's message. Disconnect Monitor's answer wasn't reached |
| Terminate with confirmation | Not tried: Vibeshine only shows Terminate to a second client while another one's game runs |
| Sleep the PC | Not possible on this host: Vibeshine 2.0.1 answers 404 for `/power-actions/v1` and its serverinfo has no power fields, so the app doesn't offer it |
| Hardware metrics in the overlay | Not possible on this host: 404 for `/api/hardware-metrics`, no `HardwareMetricsVersion` |
| Demo mode | `testDemoMode`: the demo PC, its apps, a stream of the generated picture (295 frames by the time it was read) and 6 touch events (down and up) from 3 taps |

The PC's answers recorded for the tests (serverinfo in both views, the app list, `/bitrate`, the
ABR capabilities and the errors) are in `ios/StarwireKit/Tests/StarwireKitTests/Fixtures`, with
the PC's address, MAC and IDs replaced.

## Problems

1. **A secret scanner flagged a test fixture.** The power actions fixture had a made-up
   64-character sleep token. Nothing real was in it (this Vibeshine never issues one). Replaced
   with a plain pattern; the runbook now says to check what `mac.sh sync` publishes.
2. **Simulator tests had no Keychain** (error -34018) when built unsigned. They're now signed ad
   hoc, in `mac.sh unit` and in CI.
3. **A crash in the new HTTPS transport's tests:** it made a URL session while being freed.
   Fixed before any device run; the transport is now closed by its owner.
4. **The statistics overlay was off in the app's settings,** so the first device test saw no
   overlay. The device runs now turn it on for their own launch (`-StarwireStatsOverlay YES`).
5. **Remote Monitor failed on the PC**, as above. Not investigated further, since it changes the
   PC's display setup. After the test only DISPLAY1 (5120x1440) was active; the display change
   Vibeshine asked for listed only DISPLAY1 and the new virtual display, so the S90D (DISPLAY2)
   looks to have been off before. Not confirmed with the owner yet.
6. **The command checker for Claude Code's auto mode failed for a while**, which stopped the
   batch twice. Nothing to do with the app.

## Parity rows this run verifies

Virtual display (`virtual_display_mode`), the scale factor and VRR request, the mid-stream
bitrate, Remote Input, the demo mode, and the Keychain move for pairing. Built but not verified:
Remote Monitor, Terminate, sleep, hardware metrics, the settings JSON, per-game settings and the
exact frame rate. See [parity.md](../parity.md).

## Not checked

Pairing again with a PIN, the PC's own monitor (`virtualDisplay=0`), the pair-state grace on a
real refusal, the mDNS change on the iPad (unit tested only), and H.264.
