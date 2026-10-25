# Device run: feature/ios-batch-1, 2026-10-25

The first run of batch 1, driven entirely from the Windows PC with `ios/scripts/mac.sh` (the Mac
runbook's new first section): every build, install and test on the Mac and the iPad was started
over SSH, with nobody at the Mac. The owner re-paired the iPad once (the iPadOS 27 update had
removed the app) and was using the PC during the runs.

## What was run

| | |
| --- | --- |
| Date and time (UTC) | 25 Oct 2026, about 02:50 to 04:30 |
| Branch and commit | `feature/ios-batch-1`, `4b1418fc` for the first A/B, `aceb5588` for the long A/B |
| Who ran it | Claude Code on the Windows PC, through `mac.sh` |
| Mac | MacBook Air (M1, 2020), macOS 27.0.1 |
| Xcode | Xcode 27.0, build 27A266a |
| XcodeGen | 2.46.0 |
| iPad | iPad Pro 11-inch (M4), `iPad16,3`, iPadOS 27.0.1 (24A446) |
| Bundle ID and signing | `io.github.shev0k.starwire`, the free personal team used before |
| Build configuration | Release on the iPad; Debug for the simulator tests |
| PC and host | Vibeshine 2.0.1 (`f078104b`), RTX 5090. Every stream went to a Vibeshine virtual display at the stream's size (Vibeshine's default `per_client` mode), not the 480 Hz monitor the earlier runs streamed |
| Network | iPad on Wi-Fi, same router channel as before; PC wired. Since the pacing run the owner turned off AirDrop, Handoff and Universal Control on the iPad and the Mac, restarted the iPad, and it updated to iPadOS 27.0.1 |
| Content | The Vibeshine app "Starwire test pattern": testufo.com in a Chrome kiosk window on the virtual display |

## Build and install

| Step | Result | Notes |
| --- | --- | --- |
| Submodules and `xcodegen generate` | pass | In the agent's own checkout, `~/Developer/Starwire` |
| Device build | pass | Signed through a one-off launchd job in the logged-in session (the keychain is locked to SSH). No `-Wformat` warnings left in the files this batch touched |
| Installed over the old copy (not deleted) | first install | The iPadOS 27.0.1 update had removed Starwire and its test runner. Installed fresh with `devicectl device install app`; nothing was uninstalled |
| Pairing kept after install | no, re-paired | The owner trusted the developer, allowed Local Network, entered the PIN and set the app's settings again: Safe Area (2420x1668), 120 FPS, HEVC, 70 Mbps, frames to buffer 2, Statistics Overlay on |
| App starts | yes | |

## Tests

| Test | Result | Notes |
| --- | --- | --- |
| `swift test` for StarwireKit | not run | No StarwireKit change in this batch |
| Unit tests on the simulator (`StarwireTests`) | 107 passed, 0 failed | iPhone 18 Pro simulator, through `mac.sh unit` |
| Device-run UI tests on the iPad | all passed or skipped as listed below | One picture in picture run was skipped before the test was fixed (see Problems) |

## The stutter

**Before (25 Oct pacing run):** 12% to 15% of frames dropped, about two 50 to 140 ms freezes a
second, network latency swinging 4 to 27 ms. The run measured the gaps after decoding only.

**Now:** the stutter is gone in every presenter. The render loop alone (the old default) showed
120 FPS with 0.00% to 0.01% drops, every frame on screen for 8.3 ms, and network latency 3 to 5 ms
with a variance of 0 to 1 ms.

What changed between the two runs, all at once, so the cause can't be pinned to one of them:
AirDrop, Handoff and Universal Control off on both devices, an iPad restart, iPadOS 26.6.2 to
27.0.1, and the stream source (the 480 Hz monitor then, a 120 Hz virtual display now). The network
measurement added in this batch (from the frames' packets, before decoding) now sees 0 to 9 holes
of about 50 to 70 ms in a 5 minute stream, in bursts, against about two a second before. The host's own frame times had no gaps after the start in any run, so what is
left comes from the network, not the host. That fits the AWDL explanation of moonlight-ios
issue #627, but this run didn't test the settings one at a time.

## The A/B runs

Display presenter with each jitter buffer, against the render loop. Same settings as above;
`PRESENTER` and `JITTER_BUFFER` as listed. "Decode to screen" is the mean from the end of decoding
to the frame appearing; "1% low" is the worst 5 second window of the stream.

**5 minutes each (the decision):**

| Run | Drops | Shown for 8.3 ms | 1% low | Decode to screen | Network to screen | Frames held | Network holes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Render loop (old default) | 0.00% | 100.0% | 100 FPS | 34.5 ms | 40.1 ms | 2 (queue) | 1 |
| Display, lowest latency | 0.23% | 99.8% | 60 FPS | 19.3 ms | 24.8 ms | 0 | 0 |
| Display, low latency | 0.01% | 100.0% | 100 FPS | 22.6 ms | 28.2 ms | 0.48 mean | 1 |
| Display, balanced | 0.08% | 100.0% | 50 FPS | 23.8 ms | 29.3 ms | 0.63 mean | 5 |
| Display, smooth | 0.03% | 100.0% | 75 FPS | 45.4 ms | 51.0 ms | 3.03 mean | 9 |

**2 minutes each (first pass):**

| Run | Drops | 1% low | Decode to screen | Network holes after the start |
| --- | --- | --- | --- | --- |
| Render loop | 0.00% | 119.9 FPS | 32.6 ms | 0 |
| Display, lowest latency | 0.19% | 37.5 FPS | 17.3 ms | 3 (up to 64 ms) |
| Display, low latency | 0.20% | 54.5 FPS | 21.8 ms | 5 (up to 50 ms) |
| Display, balanced | 0.22% | 50.0 FPS | 26.6 ms | 6 (up to 71 ms) |
| Display, smooth | 0.01% | 100.0 FPS | 34.5 ms | 0 |

"Network holes" counts gaps of more than 2.5 frames in the packets after the start of the
stream; they came in bursts, so the runs met different numbers of them (0 to 9). Lowest latency
drops a frame whenever two decoded frames land in one refresh, with or without holes; low latency
shows them in order instead, for about 3 ms more. Smooth met the most holes and still dropped
only 0.03%, but it holds about 3 frames, 23 ms more than low latency.

**The new default: the display presenter with the low latency jitter buffer.** It was as smooth
as the render loop on this network (0.01% drops, 1% low 100 FPS) with about 12 ms less from
decode to screen. A 30 second stream with no test choices set confirmed it: display presenter,
low latency, 0.03% drops. Low latency only met one hole in its 5 minutes, so on patchier Wi-Fi
smooth is the better choice; the setting is in iOS Settings > Apps > Starwire. The render loop
stays as a test choice.

## Video features (phase 4)

30 second streams, display presenter, lowest latency unless listed.

| Feature | Result |
| --- | --- |
| AV1 | 2420x1668 AV1 at 120 FPS, 0.10% drops, 16.5 ms decode to screen |
| HEVC 4:4:4 | "HEVC (4:4:4)" at 119.8 FPS, 0.18% drops, 15.6 ms |
| Full range | Streams at 120 FPS, 0.03% drops. Colours not checked by eye |
| HDR10 with EDR | The host sent "HEVC Main 10 HDR" to the virtual display; 120 FPS with a dip to 94, 0.58% drops, 25.2 ms. Not checked by eye |
| Lite overlay | One line: "119.9 FPS, 1% low 120, drops 0.0% / 0.0%, latency 3 ms, decode 5.7 ms, display 120 Hz" |
| Measured refresh, 60 FPS | Display at 120 Hz (refresh 8.33 ms). Before the fix in this batch, 60 FPS on 120 Hz alternated 8.3 and 25 ms frames (only 50% to 89% of frames on screen for 16.7 ms); after it, 99.9% at 16.7 ms, 20 ms decode to screen |
| Refresh rate reduction | 60 FPS with reduction: display at 60 Hz (refresh 16.67 ms), 99.9% at 16.7 ms, 27.5 ms decode to screen |
| Frame interpolation | 1080p60: 1953 frames made, none failed, 14.5 ms each; 120 FPS on screen, 100% at 8.3 ms, 0% drops, 35 ms decode to screen. At 2420x1668 the system refuses it: the M4 allows up to 1920 on a side and 2,073,600 pixels. The first try dropped 45% (fixed, see Problems) |
| Picture in picture | After the Home button, picture in picture started and the stream kept going; coming back closed it ("closed, started 1"). How it looks not checked by eye |
| External display | Not checked: no display was connected to the iPad |
| Background and resume | `testBackgroundAndResume` passed (left the app by opening Settings) |
| Streams in a row | `testStreamsInARow`: 10 of 10, no alert, no crash (235 s) |

## Problems

1. **The test runs turned off the PC's monitors** and could take its sound: Vibeshine's default
   virtual display layout (`exclusive`) does that for every stream, and "play audio on PC" off
   moves the PC's audio to the stream. Fixed for the tests only: the test pattern app uses the
   `extended_isolated` layout and the tests ask for the PC's audio to stay on the PC. Normal
   streams keep the host's defaults.
2. **The overlay's audio bitrate showed billions of kbps** (and the decode time "nan" or 0.00).
   Fixed, with regression tests.
3. **Frame interpolation dropped 45% of frames** at first: its made-up frame arrives with the real
   one and "lowest latency" shows only the newest. Fixed: it shows them in order.
4. **60 FPS on the 120 Hz display juddered** with the display presenter. Fixed, as above.
5. **Picture in picture stayed up after returning to the app.** Fixed: it closes on return.
6. **XCUITest can't always send the app to the background on iPadOS 27.** Opening Settings left
   Starwire in the foreground once (windowed apps); the tests now try the Home button first and
   skip, rather than pass, when the app never left. One picture in picture run was skipped this
   way before the fix.
7. **The Mac slept between runs.** Its power settings say `sleep 1`; SSH dropped mid-batch and
   two tests ran at once until they were stopped. `mac.sh test` now runs detached and is polled,
   and a time-limited `caffeinate` keeps the Mac awake during a batch.
8. **One summary test failed** after a new field was added; Xcode then spent minutes collecting
   simulator diagnostics. Fixed the test, and `mac.sh unit` no longer collects them.

## Parity rows this run verifies

Jitter buffer presets, YUV 4:4:4, AV1 and HEVC, reduce refresh rate and measured refresh rate,
Full and Lite overlay with 1% low, picture in picture, frame interpolation, and the settings
`jitter_buffer`, `checkbox_enable_pip`, `checkbox_reduce_refresh_rate`, `video_format`,
`checkbox_enable_perf_overlay` and `checkbox_enable_perf_overlay_lite`. HDR10, full range and
external display stay "built" (see [parity.md](../parity.md)).

## Not checked

Picture quality by eye (HDR, full range, 4:4:4), how picture in picture feels, an HDR game, an
external display, H.264, the settings one at a time for the stutter, the 480 Hz monitor as the
stream source, and an Instruments trace.
