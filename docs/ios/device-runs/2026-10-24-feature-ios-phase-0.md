# Device run: feature/ios-phase-0, 2026-10-24

The first run of [the Mac runbook](../mac-runbook.md). The stream checks were driven by a local
UI test (XCUITest) on the iPad, not by hand, except for pairing and one manual stream by the owner.
See "How the checks were run" below.

## What was run

| | |
| --- | --- |
| Date and time (UTC) | 24 Oct 2026, 22:30 to 23:08. Test stream 22:59:08 to 23:04:51 |
| Branch and commit | `feature/ios-phase-0` at `82ec1bef65` |
| Who ran it | Claude Code on the Mac. The owner paired the iPad and ran one stream by hand |
| Mac | MacBook Air (M1, 2020), `MacBookAir10,1`, macOS 27.0.1 (26A434) |
| Xcode | Xcode 27.0, build 27A266a, iOS 27.0 SDK, Metal Toolchain 27A266a |
| XcodeGen | 2.46.0, built from source (Homebrew isn't installed on this Mac) |
| iPad | iPad Pro 11-inch (M4), `iPad16,3`, iPadOS 26.6.2 (23G90), named "mimi love" |
| Bundle ID and signing | `io.github.shev0k.starwire`, free personal team. The fallback ID wasn't needed |
| Build configuration | Release |
| PC and host | Vibeshine, latest release (exact version not checked), RTX 5090, Ryzen 9 9950X3D. The streamed display runs at 480 Hz (testufo.com said so); its resolution was not checked |
| Network | iPad on Wi-Fi (band not checked; the owner says the link runs at about 1 Gbit/s). PC wired |

## Build and install

| Step | Result | Notes |
| --- | --- | --- |
| Submodules and `xcodegen generate` | pass | The four iOS submodules only. Needed XcodeGen first, see "Changes to the runbook" |
| Device build | pass | First try failed: `cannot execute tool 'metal' due to missing Metal Toolchain`. Passed after `xcodebuild -downloadComponent MetalToolchain` (839 MB). 81 warnings, all compiler warnings in upstream and third-party C/C++/Objective-C (enet enum mixing, unused variables, deprecated `keyWindow`). None about signing |
| Installed over the old copy (not deleted) | yes | First install with `devicectl` (no copy was there). Later `xcodebuild test` runs installed over it four times. Nothing was ever uninstalled |
| Pairing kept after install | yes | Paired by the owner after the first install. Every later install opened straight into the paired host's app list |
| App starts | yes | Only after trusting the developer. Before that, launch fails with "its profile has not been explicitly trusted by the user" |

## Tests

| Test | Result | Notes |
| --- | --- | --- |
| `swift test` for StarwireKit | 1 passed, 0 failed | `KitInfoTests.testCurrentMatchesTheProjectDeploymentTarget` |
| Simulator build | pass | Debug, `generic/platform=iOS Simulator`, no signing. 130 warnings |
| App tests on the iPad | none yet | The app has no test target. The local UI test below is not in git |

## Stream

From the automated run, 18 samples of the overlay text, one every 15 seconds.

| | |
| --- | --- |
| App streamed | Desktop |
| Resolution and frame rate asked for | 2420x1668 ("Safe Area", the iPad's native size), 120 FPS |
| Codec, HDR, chroma | HEVC, off, 4:2:0. Overlay confirms "Codec: HEVC" |
| Bitrate | 70.0 Mbps set. The overlay showed 34.7 to 38.5 Mbps average, 51.8 to 56.2 peak |
| Length of the stream | 4 min 32 s to 4 min 47 s: not running at 31 s after the tap, running at 46 s, stopped at about 318 s. That is short of the runbook's 5 minutes. Plus 25 s in the background test |
| Frame rate shown, start and end | 101.72 FPS at 46 s, 105.32 FPS at 302 s. Mean 104.76 |
| Dropped frames (network, pacing) | Network 0.0% in every sample. Pacing jitter 12.1% to 13.5%, mean 12.66% |
| Decode time | Average 5.27 to 5.45 ms. Max 29.04 ms in the first sample, then 7.51 to 8.16 ms |
| Network latency | 4 to 25 ms average (variance 2 to 27 ms), mean 12 ms. Host processing 2.2 to 2.8 ms |
| Visible problems | None visible in the end screenshot. Nobody watched the iPad during the run, so stutter, tearing, input lag and audio were not checked by eye. Audio: see Problems |
| Background and resume | worked. Switching to the Settings app ended the stream (the code does this on purpose in `applicationDidEnterBackground`). Coming back showed the app list, no crash |
| Stopping the stream | clean. A swipe from the left edge returned to the app list, the app stayed in the foreground |

What the numbers mean: the overlay's FPS is frames shown, which is frames received minus network
drops minus pacing drops (`StreamManager.m`, `getStatsOverlayText`). 104.76 shown with 12.66%
dropped by pacing means about 120 FPS arrived and the renderer dropped about one frame in eight.
So HEVC at 120 Hz reaches the iPad, but it doesn't all reach the screen.

The overlay text at 302 s, word for word:

```
Video stream: 2420x1668 105.32 FPS (Codec: HEVC) Audio stream: 2ch Opus @ 0 kbps
Bitrate: 35.4 Mbps, Peak: 53.2, Frame queue: 1.9 Audio buffer: 100% full (85.33 ms)
Host processing latency min/max/avg: 2.2/2.7/2.3 ms Audio decode: nan ms
Frames dropped by network/pacing jitter: 0.0% / 12.5%
Average network latency: 21 ms (variance: 24 ms)
Decode time: 3.90/7.56/5.41 ms
```

Settings read from the app before the run: Safe Area (2420 x 1668), 120 FPS, 70.0 Mbps, HDR No,
4:2:0, HEVC, Stereo, Frames to buffer 2, Statistics Overlay Yes, Touchpad mode.

Screenshots:
- `2026-10-24-feature-ios-phase-0-1.png`: the owner's manual stream at 22:42 UTC. Black
  wallpaper with a static desktop: 14.39 FPS, 0.2 Mbps, pacing drops 5.7%, latency 18 ms, decode
  5.01 ms average.
- `2026-10-24-feature-ios-phase-0-2.png`: the iPad at 302 s of the automated run, showing the
  testufo.com moving content on the PC. Cropped to the page; the overlay text is quoted above.
- `2026-10-24-feature-ios-phase-0-3.png`: the app list after the stream was stopped.
- `2026-10-24-feature-ios-phase-0-4.png`: the "Resume App / Quit App" menu, 31 s after tapping
  Desktop (see Problems).

Not committed, because the repo is public: the full screenshot at 302 s (it shows the PC's browser
tabs and bookmarks) and the background screenshot (it shows the Apple ID's email in iPad
Settings). They stay on the Mac.

## Problems

1. **One frame in eight dropped by pacing at 120 FPS.** 12.1% to 13.5% in all 18 samples, with 0%
   network drops and a frame queue of 1.5 to 1.9. Steady over 5 minutes. Frames to buffer was 2.
   Not investigated; phase 4 rebuilds pacing on the Metal presenter.
2. **Audio showed 0 kbps the whole time**, with "Audio decode: nan ms" and the buffer "100% full".
   The PC page (testufo.com) makes no sound and "Play Audio on PC" was No, so this may just mean
   silence. Not checked with sound playing.
3. **Static desktop gives about 15 FPS.** The host only sends new frames when the picture
   changes. The 120 FPS check needs moving content on the PC (testufo.com here).
4. **"Resume App / Quit App" menu instead of an immediate stream.** In the automated run, 31 s
   after tapping Desktop the screen showed this menu over the Desktop tile (screenshot 4) and no
   stream. By 46 s the stream was running with no further taps. Desktop was still running on the
   host from an earlier session. Seen once, cause not investigated.
5. **Owner's manual session (22:38 to 22:45 UTC).** Read from the console log:
   - Every request to `http://<PC's LAN address>:47989/serverinfo` timed out, and to the PC's
     public address on the same port was refused, the whole session, yet pairing and streaming
     worked. Lines like (address removed):
     `Task <...> finished with error [-1001] ... NSErrorFailingURLStringKey=http://<LAN address>:47989/serverinfo`
   - At 22:44:49 UTC the app tried to show a second alert over the first:
     `Attempt to present <UIAlertController: 0x1542be400> on <SWRevealViewController: 0x1039722c0> (from <StreamFrameViewController: 0x155af8500>) which is already presenting <UIAlertController: 0x1542bde00>.`
     The app was then stopped with `App terminated due to signal 9`. Signal 9 is what a force-quit
     from the app switcher looks like; the owner didn't note what the alert said.
   - At launch: `` `UIScene` lifecycle will soon be required. Failure to adopt will result in an assert in the future. `` Phase 1 already plans the UIScene lifecycle.
6. **No app log in Release.** `Logger.h` compiles `Log()` out unless `DEBUG` is set, so a Release
   run only shows system lines. The overlay is the only measurement source in Release.

## Parity rows this run verifies

None. Every row in [parity.md](../parity.md) belongs to phase 1 or later and is still `planned`;
a row has to be `built` before a report can verify it. This run covers the phase 0 "Done when"
items in [port-plan.md](../port-plan.md): the Mac installs the app on the iPad, the upstream UI
pairs and streams Desktop with HEVC, and this report records frame rate and drops. About 120 FPS
arrives; about 105 FPS reaches the screen.

## How the checks were run

The owner asked for the stream checks to be automated. A UI test target was added to a local
XcodeGen spec (`ios/devicerun.yml`, which includes `project.yml`; the test lives under `build/`,
which git ignores) and run with `xcodebuild test -configuration Release` on the iPad. It reads
the settings screen, taps Desktop, reads the overlay label's text every 15 seconds for 5 minutes,
takes screenshots, switches to the Settings app and back, and swipes from the left edge to stop.
The owner only opened testufo.com on the PC. Neither file is committed. Phase 1, which adds app
tests, can take it over.

## Changes to the runbook

- Prerequisites: listed the macOS and Xcode actually used, added the Metal Toolchain (the device
  build fails without it), and said how to build XcodeGen from source when Homebrew isn't there.
- Signing: Xcode can hold more than one personal team; pick the one for the owner's Apple ID.
- Install and launch: the first launch fails until the developer is trusted; the app asks for
  Local Network access; Release builds have no app log, and `OS_ACTIVITY_DT_MODE` is needed to see
  even the system lines with `--console`.
- Device checks: moving content on the PC is needed for frame rate numbers; what the overlay's
  FPS means; how the background check works; what the UI test does.
- Report: don't commit screenshots that show the PC's browser or the Apple ID.
