# Device run: feature/ios-phase-1a, 2026-10-25

The second run of [the Mac runbook](../mac-runbook.md), for the phase 1a checks in its section 7a.
All stream checks were driven by the `StarwireDeviceRun` UI tests on the iPad. The owner opened
testufo.com on the PC, quit Desktop on the PC once, and answered questions; nobody watched the
iPad during the runs.

## What was run

| | |
| --- | --- |
| Date and time (UTC) | 25 Oct 2026, about 00:05 to 00:40. A/B runs 00:16:37 to 00:30:16, stability tests 00:34:10 to 00:38:06 |
| Branch and commit | `feature/ios-phase-1a` at `b7f90a21e2` |
| Who ran it | Claude Code on the Mac |
| Mac | MacBook Air (M1, 2020), macOS 27.0.1 (26A434) |
| Xcode | Xcode 27.0, build 27A266a |
| XcodeGen | 2.46.0, built from source (no Homebrew on this Mac) |
| iPad | iPad Pro 11-inch (M4), `iPad16,3`, iPadOS 26.6.2, named "mimi love" |
| Bundle ID and signing | `io.github.shev0k.starwire`, free personal team (the same one as the first run) |
| Build configuration | Release on the iPad; Debug for the simulator tests |
| PC and host | Vibeshine (version not checked), RTX 5090. Streamed display: the 480 Hz monitor (testufo.com showed 479 fps, 480 Hz) |
| Network | iPad on Wi-Fi (band not checked), PC wired |

## Build and install

| Step | Result | Notes |
| --- | --- | --- |
| Submodules and `xcodegen generate` | pass | `git submodule sync --recursive` first: common-c now comes from `shev0k/moonlight-common-c`, branch `starwire-ios`, at `cb925b1909` |
| Device build | pass | 73 warnings, all compiler warnings (format specifiers, documentation comments, field order in C++ initializers). None about signing |
| Installed over the old copy (not deleted) | yes | `devicectl device install app`, then `xcodebuild test` installed over it. The Starwire app was never uninstalled. To make room for the new test runner, the old phase 0 runner (`io.github.shev0k.starwire.uitests.xctrunner`) was uninstalled, with the owner's OK. See Problems |
| Pairing kept after install | yes | Every launch opened straight into the PC's app list; the log says "Already Paired" |
| App starts | yes | |

## Tests

| Test | Result | Notes |
| --- | --- | --- |
| `swift test` for StarwireKit | 1 passed, 0 failed | |
| Simulator build | pass | Built by the unit test run below (Debug, iPhone 18 Pro simulator, no signing). The separate `generic/platform=iOS Simulator` build was not run |
| Unit tests on the simulator (`StarwireTests`) | 39 passed, 0 failed | 66 warnings in the log |
| Device-run UI tests on the iPad (`StarwireDeviceRun`) | 6 passed, 1 failed, 2 stopped | One more try didn't install (Problems 3). The first try that ran failed on the Desktop tile lookup (Problems 2). All passing runs used a local, uncommitted fix to that lookup. Runs A to D and both stability tests passed; the two E attempts were stopped by hand |

## Stream

From run B (the branch's defaults), 120 seconds, a sample every 15 seconds.

| | |
| --- | --- |
| App streamed | Desktop |
| Resolution and frame rate asked for | 2420x1668, 120 FPS. The app's settings were not read again this run; the overlay confirms 2420x1668 and HEVC |
| Codec, HDR, chroma | HEVC, off, 4:2:0 |
| Bitrate | 70 Mbps set in the first run, not read again. The overlay showed 30.5 to 43.8 Mbps average |
| Length of the stream | Run A 300 s, runs B to D 120 s each (shortened to save time, see "Changes to the runbook") |
| Frame rate shown, start and end | 105.67 FPS at 15 s, 105.28 FPS at 120 s, mean 105.1 |
| Dropped frames (network, pacing) | Network 0.0% in every sample of every run. Pacing 11.7% to 13.1%, mean 12.25% |
| Decode time | Average 5.31 to 5.40 ms, max 7.39 to 7.83 ms after the first sample |
| Network latency | 5 to 26 ms average, mean 14 ms |
| Visible problems | Not checked by eye: nobody watched the iPad. Audio showed 0 kbps again, with no sound playing on the PC |
| Background and resume | worked (`testBackgroundAndResume` passed) |
| Stopping the stream | clean, in every run (edge swipe, app list back, no alert) |

The overlay at 120 s of run B, word for word:

```
Video stream: 2420x1668 105.28 FPS (Codec: HEVC) Audio stream: 2ch Opus @ 0 kbps Bitrate: 30.5 Mbps, Peak: 46.0, Frame queue: 1.9 Audio buffer: 100% full (85.33 ms) Host processing latency min/max/avg: 2.3/2.5/2.3 ms Audio decode: nan ms Frames dropped by network/pacing jitter: 0.0% / 12.5% Average network latency: 16 ms (variance: 15 ms) Decode time: 4.46/7.39/5.34 ms Pacing: bursts 0.0%, drops after burst 0, held 2+ refreshes 1.9%, skipped 0
```

Screenshots:
- `2026-10-25-feature-ios-phase-1a-1.png`: the iPad at the end of run B, showing testufo.com
  moving on the PC. Cropped to the page: the full screenshot shows the PC's browser tabs and
  bookmarks, so it isn't committed. The overlay text is quoted above.

## Pacing

Settings for every run: 2420x1668, 120 FPS, HEVC, testufo.com moving on the PC's 480 Hz monitor.
Means leave out the sample at 0 s, which is taken the moment the overlay appears (it showed 15 to
110 FPS and a decode max near 30 ms in every run). Frames to buffer 2 for A to C is the app's
setting from the first run, not read again; the frame queue (1.6 to 1.9, against 2.2 to 2.7 with
buffer 3) agrees.

| Run | Settings | Pacing drops, at 60 s / end / mean | Pacing line (bursts, drops after burst, held 2+, skipped) | Latency, decode |
| --- | --- | --- | --- | --- |
| A | frame, alternate, buffer 2 | 10.9% / 12.3% (300 s) / 11.61% (20 samples) | 0.0%, 0, 1.7% to 1.9%, 0 | 4 to 27 ms (mean 12), 5.44 to 5.55 ms |
| B | nearest, alternate, buffer 2 | 11.9% / 12.5% (120 s) / 12.25% (8 samples) | 0.0%, 0, 1.7% to 1.9%, 0 | 5 to 26 ms (mean 14), 5.31 to 5.40 ms |
| C | nearest, newest, buffer 2 | 12.1% / 12.3% (120 s) / 11.95% (8 samples) | 0.0% to 0.2%, 0, 1.9%, 0 | 6 to 24 ms (mean 14), 5.31 to 5.40 ms |
| D | nearest, alternate, buffer 3 | 9.6% / 11.3% (120 s) / 10.20% (8 samples) | 0.0%, 0, 1.8% to 1.9%, 0 | 7 to 27 ms (mean 16), 5.31 to 5.38 ms |
| E | B plus virtual display | not run | | |

Frames shown, mean: A 105.7, B 105.1, C 105.7, D 107.6 FPS.

E was tried twice and stopped both times, because the PC never switched to a virtual display.
The first try resumed the Desktop session that was still running on the PC from run D, which
stays on the display it started on. The owner then quit Desktop and the second try launched it
fresh (no Resume menu came up), but Vibeshine still streamed the 480 Hz monitor (testufo.com on
the PC still said 480). The owner thinks a Vibeshine setting is the cause; not checked. Both
tries showed the same numbers as B at 15 s (11.5% and 11.9%).

The `pacing window` log lines were not collected: `log collect` from the iPad needs root on the
Mac. The numbers above are from the overlay only.

**What the numbers say about the cause.** None of the runbook's three theories fits.
- Not the present timing: A (the old rule) and B (the fix) are the same, about 12%.
- Not bursty arrival: bursts were 0.0% (0.2% in one sample) and "drops after burst" was 0 in
  every sample of every run, so frames reach the queue evenly.
- Not the drop policy: C is the same as B.
- Not the network: 0% network drops, and decode averages about 5.4 ms, well under the 8.33 ms a
  frame has at 120 FPS.

What is left is the consumer: something on the iPad takes frames off the queue at about 106 a
second, and has done so at every setting. The "held" counter points at how. If the screen were
refreshing at a fixed 120 Hz and the consumer simply missed refreshes, about 14 frames in 106
would be held for two refreshes, which is 13%. The counter says 1.9%. So the time between
presented frames averages about 9.4 ms (1/106 s), 1.13 refreshes, and almost all of those gaps
count as "one refresh" (under 1.5). Either the screen isn't refreshing at a steady 120 Hz while
streaming, or the presented times don't fall on whole refreshes. That points at the render loop
and the display link setup in `MetalViewController.m` (the manual loop that waits for a drawable,
then for a frame, then dequeues with a timeout of one frame minus the average GPU time), not at
pacing policy. This is a reading of the counters, not a measurement of the cause. The next step
is an Instruments trace with the `pacing` signposts and Core Animation's frame rate, or the
`pacing window` lines from a `sudo log collect`.

The owner reports that Artemis on an Android phone, streaming the same 480 Hz monitor from the
same PC, doesn't show this drop. Not measured in this run; it agrees with the cause being on the
iPad side.

**Best setting found.** Buffer 3 (run D) had the fewest drops, 10.2% against 11.6% to 12.3%, and
the most frames shown, 107.6. It is still ten times the 1% goal and adds a frame of latency, so
it isn't worth it. Among the buffer 2 settings (A, B, C) there was no real difference. The goal
of under 1% pacing drops was not reached with any setting tried.

## Stability, serverinfo and logs

| Check | Result | Notes |
| --- | --- | --- |
| Streams in a row (`testStreamsInARow`) | 10 of 10 | No alert and no crash; the app stayed in the foreground after every stream. 196 s in all |
| Background and resume (`testBackgroundAndResume`) | pass | No alert. 34 s |
| PC shown online in the app | yes | The app opened straight into the PC's app list on every launch, and the log says "Already Paired" and "App list successfully retreived". The PC list screen itself was not looked at |
| curl HTTP 47989 / HTTPS 47984 serverinfo from the Mac | HTTP 200 in 0.023 s / HTTPS no answer | HTTPS: the PC closed the connection in the TLS handshake after 0.12 s (curl exit 56), with no HTTP status. That is the client certificate check; the runbook expected 401 or 403 |
| App log lines visible in Release | yes | From `devicectl ... --console`. For example: `Starwire[2672:943182] [network] <INFO> Starting mDNS discovery` |

The 15 seconds of console log also show the app still sending some HTTP serverinfo requests to
port 47989. One timed out and one connection was refused (addresses removed):

```
[network] <WARN> Request to http://<PC address>:47989/serverinfo failed: NSURLErrorDomain (-1001)
Task <...> HTTP load failed, 0/0 bytes (error code: -1004 [1:61])
```

The curl from the Mac to the same port answered at the same time, so this is not the PC failing.
Which code path sends these requests was not checked.

## Problems

1. **About 12% pacing drops at every setting.** See Pacing. The phase 1a goal of under 1% was
   not met, and this branch's fix (nearest present timing) made no difference.
2. **The device-run tests can't find the Desktop tile.** `StreamDeviceRunTests` looks for an
   element with `label == "Desktop"`. The Desktop tile shows box art and no element has that
   label, so the first try failed after 30 s with "no "Desktop" tile: is the PC paired, awake and
   showing its app list?" while the app list was on screen. For this run the lookup was changed
   locally, and not committed, to the first cell of the collection view (Desktop is first, as in
   the phase 0 local test). The tests need that fix in git.
3. **The free account's 3 app limit.** Installing the new test runner
   (`io.github.shev0k.starwire.devicerun.xctrunner`) failed with "This device has reached the
   maximum number of installed apps using a free developer profile". The three were Starwire,
   the phase 0 runner and another free-signed app of the owner's. With the owner's OK the phase 0
   runner was uninstalled.
4. **Virtual display not used.** See Pacing, run E. Not investigated on the PC.
5. **The app still sends HTTP serverinfo requests** that time out or are refused, while the
   same port answers curl from the Mac. See above. Pairing, the app list and streaming all
   worked.
6. **Audio 0 kbps**, as in the first run. No sound was playing on the PC; not checked with sound.
7. **"Loading frame already shown!"** is logged as an error at every launch. No visible effect
   seen; not investigated.

## Parity rows this run verifies

None. No row in [parity.md](../parity.md) is `built` yet, so none can be verified.

## Changes to the runbook

- Section 1: run `git submodule sync --recursive` before the submodule update when
  `.gitmodules` has moved a submodule (common-c moved to `shev0k/moonlight-common-c`).
- "Reading the app's log": `log collect` from an attached device needs root, not just maybe; in
  zsh `log` is a shell built-in, so call `/usr/bin/log`; and `devicectl list devices` printed the
  UDID as the identifier on this Mac, so `$IPAD` and `$IPAD_UDID` were the same.
- Section 6: the free account's 3 app limit now includes the test runner; remove the old phase 0
  runner if it is still installed. After the first run, use `test-without-building` to skip the
  build. The sample at 0 s isn't representative; leave it out of means.
- Section 7a: run E needs Desktop quit on the PC first, or the test resumes the old session on
  the old display; and check on the PC that the display really changed. A shorter stream
  (`TEST_RUNNER_STARWIRE_SECONDS=120`) is enough when the drop rate is steady, and the report
  says so. Added a row to "How to read a window" for what this run showed.
- Section 7a, serverinfo: an HTTPS check without a client certificate ends in the handshake
  (curl exit 56, code 000), not a 401 or 403.
- Section 7a, logs: the example line (`Pacing: frames to buffer ...`) wasn't in the 15 seconds of
  launch log, since no stream ran; a launch line is the example now. Whether that line is logged
  at stream start was not checked.
- Section 8: the commit command used the phase 0 message; it now names the branch.
