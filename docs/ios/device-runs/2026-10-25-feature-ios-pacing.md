# Device run: feature/ios-pacing, 2026-10-25

The third run of [the Mac runbook](../mac-runbook.md), for the pacing checks in its section 7a.
Stream checks were driven by the `StarwireDeviceRun` UI tests on the iPad. The owner opened
testufo.com on the PC and watched the iPad. After run L and two partial D runs the owner stopped
the session, so most of the planned checks were not run (see "What wasn't run").

## What was run

| | |
| --- | --- |
| Date and time (UTC) | 25 Oct 2026. Run L 01:13:37 to 01:16:00, D (first try) from 01:16:09 for about 30 s of stream, D (second try) from 01:20:08 for about 45 s of stream |
| Branch and commit | `feature/ios-pacing` at `4cb99a12a9` for L and the first D try. The second D try added the arrival gap counters to the summary line, committed after the run on this branch |
| Who ran it | Claude Code on the Mac |
| Mac | MacBook Air (M1, 2020), macOS 27.0.1 (26A434) |
| Xcode | Xcode 27.0, build 27A266a |
| XcodeGen | 2.46.0, built from source |
| iPad | iPad Pro 11-inch (M4), `iPad16,3`, named "mimi love". iPadOS version not checked this run (26.6.2 in the last run) |
| Bundle ID and signing | `io.github.shev0k.starwire`, free personal team (the same one as before) |
| Build configuration | Release on the iPad; Debug for the simulator tests |
| PC and host | Vibeshine (version not checked), RTX 5090. Streamed display: the 480 Hz monitor (not checked again this run) |
| Network | iPad on Wi-Fi (band not checked), PC wired. The iPad was also plugged into the Mac by USB-C |

## Build and install

| Step | Result | Notes |
| --- | --- | --- |
| Submodules and `xcodegen generate` | pass | |
| Device build | pass | |
| Installed over the old copy (not deleted) | yes | `devicectl device install app`, then `xcodebuild test` installed over it. Nothing was uninstalled, and the 3 app limit was not hit |
| Pairing kept after install | yes | The tests found the Desktop tile with no pairing |
| App starts | yes | |

## Tests

| Test | Result | Notes |
| --- | --- | --- |
| `swift test` for StarwireKit | not checked | Not run this time |
| Simulator build | pass | Built by the unit test run below |
| Unit tests on the simulator (`StarwireTests`) | see below | Run after the counter change, before the push |
| Device-run UI tests on the iPad (`StarwireDeviceRun`) | 1 passed, 2 stopped | Run L passed. Both D tries were stopped part way (see Pacing) |

## Stream

From run L (render loop), 120 seconds, a sample every 15 seconds.

| | |
| --- | --- |
| App streamed | Desktop |
| Resolution and frame rate asked for | 2420x1668, 120 FPS. The app's settings were not read; the overlay confirms 2420x1668 |
| Codec, HDR, chroma | AV1 by the overlay, not HEVC as in phase 1a. HDR and chroma not checked. The codec setting wasn't changed in this run |
| Bitrate | Not read from the settings. The overlay showed 34.6 to 36.3 Mbps average, peaks 51 to 60 |
| Length of the stream | L 120 s. D about 30 s and about 45 s, both stopped early |
| Frame rate shown, start and end | L: 104.97 FPS at 15 s, 106.25 FPS at 120 s |
| Dropped frames (network, pacing) | Network 0.0% in every sample. Pacing: L 10.0% to 12.7%, D 13.7% to 15.6% |
| Decode time | Average 5.68 to 5.93 ms, max 7.70 to 8.62 ms after the first sample, in both presenters |
| Network latency | Average 4 to 23 ms, variance 3 to 24 ms, changing from sample to sample |
| Visible problems | The owner watched the iPad: it stuttered in L and in both D tries ("same jank"). Audio 0 kbps again, with no sound playing on the PC |
| Background and resume | not checked |
| Stopping the stream | clean in run L (edge swipe, app list back, no alert). The D tries were stopped from the Mac, not by the test |

Screenshots: none committed. Run L's two screenshots are in its result bundle on the Mac only.
They show the PC's browser, so they weren't put in the public repo.

## Pacing

Settings: 2420x1668, 120 FPS, AV1 (by the overlay), testufo.com moving on the PC. The drop
percentage "at 60 s" and "at the end" is the summary line's, which covers the whole stream so far.

| Run | Variables | Drops at 60 s / at the end | Shown for (end), 4.2/8.3/12.5/16.7/20.8/25+ ms | Refresh mean | Decode to screen mean / max | Network latency | Decode time |
| --- | --- | --- | --- | --- | --- | --- | --- |
| L | none | 11.78% / 11.75% (120 s) | 0.0/98.2/0.0/0.0/0.0/1.8%, mean 9.45 ms | 8.33 ms, off grid 0.0% | 34.6 / 41.9 ms | 6 to 23 ms | 5.68 to 5.82 ms average |
| D (first try) | `PRESENTER=display` | not reached / 14.98% (stopped at 30 s) | 0.0/98.1/0.0/0.0/0.0/1.9%, mean 9.80 ms | 8.33 ms, off grid 0.0% | 20.6 / 24.8 ms | 11 to 17 ms | 5.70 to 5.72 ms average |
| D (second try) | `PRESENTER=display`, with arrival counters | not reached / 15.44% (stopped at 45 s) | 0.0/98.0/0.0/0.1/0.0/1.9%, mean 9.85 ms, max 100.0 ms | 8.33 ms, off grid 0.0% | 20.4 / 24.9 ms | 8 to 14 ms | 5.67 to 5.68 ms average |
| D5 | display, 300 s | not run: D was not under 1% | | | | | |
| V | display, virtual display | not run: the owner stopped the session | | | | | |

The summary lines at the end, word for word:

```
L: Pacing summary (loop): 120 s, in 14728, drops 11.75% (incoming 1731, oldest 0, replaced 0), shown 12991, shown for 4.2/8.3/12.5/16.7/20.8/25+ ms: 0.0/98.2/0.0/0.0/0.0/1.8%, mean 9.45 ms, off grid 0.0%, late 0, skipped 1; refresh mean 8.33 ms, off grid 0.0%; refreshes without a new frame 0.0%; drawable wait mean 7.44 ms; decode to screen mean 34.6 ms, max 41.9 ms
D, first try, at 30 s: Pacing summary (display): 30 s, in 3813, drops 14.98% (incoming 0, oldest 0, replaced 571), shown 3236, shown for 4.2/8.3/12.5/16.7/20.8/25+ ms: 0.0/98.1/0.0/0.0/0.0/1.9%, mean 9.80 ms, off grid 0.0%, late 0, skipped 2; refresh mean 8.33 ms, off grid 0.0%; refreshes without a new frame 16.0%; drawable wait mean 0.00 ms; decode to screen mean 20.6 ms, max 24.8 ms
D, second try, at 45 s: Pacing summary (display): 45 s, in 5604, drops 15.44% (incoming 0, oldest 0, replaced 865), arrival late 8, gaps 90, max gap 141.1 ms; shown 4736, shown for 4.2/8.3/12.5/16.7/20.8/25+ ms: 0.0/98.0/0.0/0.1/0.0/1.9%, mean 9.85 ms, max 100.0 ms, off grid 0.0%, late 0, skipped 2; refresh mean 8.33 ms, off grid 0.0%; refreshes without a new frame 16.3%; drawable wait mean 0.00 ms; decode to screen mean 20.4 ms, max 24.9 ms
```

In the second D try the arrival gaps grew steadily: 33 by 15 s, 62 by 30 s, 90 by 45 s, about
two a second. The longest was 141.1 ms.

**Did the display presenter reach under 1%?** No. It dropped about 15% against the loop's
11.75%, and the owner saw the same stutter. Its decode to screen latency was lower than the
loop's, 20.4 ms against 34.6 ms, so it adds no latency; it takes about 14 ms off.

**What the numbers say about the cause.** Phase 1a's theory, frames missing refreshes by half a
refresh, is wrong. In both presenters 98% of frames were shown for exactly 8.3 ms, none for 12.5
or 16.7 ms, and about 2% for 25 ms or more. The display ran a steady 120 Hz (refresh mean 8.33 ms,
off grid 0%), and the display presenter had no late frames. So the screen isn't the problem.
The picture runs smoothly, then freezes about twice a second.

The freezes come before the presenter. The second D try counted 90 gaps of more than 2.5 frames
(20.8 ms) between frames leaving the decoder in 45 s, up to 141 ms. Decode time stayed at about
5.7 ms average and under 8.7 ms max, so the decoder isn't holding frames. They reach it late. With
the display presenter, each gap is a run of refreshes with no new frame (16.3% of refreshes), and
the frames that come in a clump after it are replaced by the newest (865). That is the "replaced"
and "refreshes without a new frame" row of the reading guide, with the cause measured. The loop
loses the same clumps a different way: its queue of 2 is full when they come, so they are dropped
as "incoming" (1731).

So frames reach the iPad in clumps with holes in them, which points at the network. Network
latency also swung from 4 to 23 ms between samples, with variance up to 24 ms, on a LAN with a
wired PC. Not measured: whether the holes are on the iPad's Wi-Fi or in what the host sends. The
owner reports that Artemis on an Android phone, streaming the same PC, doesn't stutter, which
points at the iPad side. On Apple devices a common cause of gaps like these is AWDL, the radio
that AirDrop, Handoff and Universal Control share with Wi-Fi. The iPad was plugged into the Mac
during the run. This is a likely cause, not a measured one.

**Next step.** On the iPad, turn off AirDrop receiving, Handoff, and Cursor and Keyboard, check
the Wi-Fi band, and run D again. If the arrival gaps go away, make the display presenter the
default: it has the lower latency. If they stay, check the host, for example with the virtual
display run V or an Instruments trace.

The `pacing window` log lines were not collected (`log collect` needs root), and the
Instruments trace was not run.

## Stability, serverinfo and logs

| Check | Result | Notes |
| --- | --- | --- |
| Streams in a row (`testStreamsInARow`) | not checked | The owner stopped the session first |
| Background and resume (`testBackgroundAndResume`) | not checked | The owner stopped the session first |
| PC shown online in the app | not checked | The PC list screen was not looked at. The tests did find the PC's app list |
| curl HTTP 47989 / HTTPS 47984 serverinfo from the Mac | not checked | |
| App log lines visible in Release | not checked | |

## What wasn't run

D for the full 120 s, D5, V (and so Vibeshine's log and version), `testStreamsInARow`,
`testBackgroundAndResume`, the serverinfo curl, the console log check, `swift test`, the
Instruments trace and `log collect`. After the second D try the owner chose to stop and have the
report written with what was measured.

## Problems

1. **Stutter in both presenters, about 12% to 15% pacing drops.** See Pacing. The cause is
   frames reaching the decoder with gaps of up to 141 ms, about twice a second.
2. **Both D tries were stopped part way.** The test process on the Mac was stopped while the owner was
   sending messages, so neither reached 120 s. The numbers were steady over the samples taken.
3. **Codec was AV1, not HEVC** as in phase 1a. Phase 1a saw the same drops with HEVC, so the
   codec isn't the cause. Why the setting changed was not checked.
4. **Audio 0 kbps**, as before. No sound was playing on the PC.

## Parity rows this run verifies

None.

## Changes to the runbook

- Section 7a: the summary line now has the arrival gaps and the longest time a frame stayed up.
  Added both to the field table, and a row to "Reading the numbers" for what this run showed.
- Section 7a, the A/B runs: tell the owner before L that it is the old loop and will stutter. In
  this run the owner watched L, took it for the fix, and lost patience before D.
