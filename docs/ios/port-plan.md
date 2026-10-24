# Starwire for iPad and iPhone: implementation plan

Written 24 Oct 2026. This is the working plan for a personal, sideloaded iOS and iPadOS client
with as much of Starwire for Android's feature set as the platform and the host allow. Nothing
here has been built yet. "Starwire iOS" is a working name.

## Ground rules from the owner

- **Personal use and sideload only.** No App Store, no TestFlight, so code may come from any of
  the projects below.
- **Host: Vibeshine** (Nonary's Sunshine fork) on Windows. The client must speak everything
  Vibeshine offers. Features that need Apollo or Vibepollo are listed separately.
- **iPad first, iPhone supported, iOS and iPadOS 17 or later.** Main test device: iPad Pro, M1 or
  newer, on Wi-Fi. There is no iPhone to test on, so iPhone layouts are checked on the simulator
  only. Controllers: DualSense, FlyDigi Apex 5, and a phone-style grip.
- **Where the work happens:**
  1. Code is written on the Windows PC and pushed to `shev0k/Starwire`, under `ios/`.
  2. GitHub Actions builds and tests it on macOS. The repo is public, so this is free.
  3. Claude Code on the owner's M1 Mac builds, signs, installs and tests on real devices.
- **Signing:** a free Apple ID by default. The work account is paid and only needed for
  capabilities a free account can't have (see [Signing](#signing-and-sideloading)).
- **Extras from VoidLink:** Apple Pencil pressure curves and frame interpolation, plus others where
  they're worth it.

## What we build on

| Piece | Source | Why |
|---|---|---|
| App shell and streaming core | [moonlight-ios](https://github.com/moonlight-stream/moonlight-ios) `02dc978`, brought in with its history | Complete, small (16k lines), easy to merge from |
| Metal renderer, frame queue, float audio, AudioUnit output | [Andy Grundman's](https://github.com/andygrundman/moonlight-ios) `andyg.ios-metal-squash` | 120 Hz pacing on iPad, decode timing, 4:4:4, HDR. It merges onto upstream with small, simple conflicts and has the only unit tests among the candidates |
| Protocol library | [Nonary/moonlight-common-c](https://github.com/Nonary/moonlight-common-c), branch `mac-pyrowave` | The author's own client library for Vibeshine: PyroWave with LZ4 and link pacing, DualSense haptics (0x5601), Steam Controller extras |
| PyroWave on Apple GPUs, VRR pacing, haptics decoding, PyroWave calibration | [Nonary/moonlight-qt](https://github.com/Nonary/moonlight-qt) | Already runs PyroWave on Apple Silicon macOS through MoltenVK with Metal sharing, at commit `186f0393`, the same one Vibeshine uses |
| Renderer hardening, PiP, external display, touch handlers, Pencil, gyro, DualSense haptics on iOS, frame interpolation | [VoidLink](https://github.com/The-Fried-Fish/VoidLink-previously-moonlight-zwm) `Integration` | Proven on many devices. Copied file by file with credit, not taken whole |
| Race fixes, pinned-certificate pairing state, input recording tests | [daniel-zn Artemis iOS](https://github.com/daniel-zn/danielzn-moonlight-ios) | Small, focused fixes and a good test pattern |
| Live-host smoke tool design, Metal HDR presenter ideas | [swift-moonlight](https://github.com/wiedymi/swift-moonlight) | Best test tooling seen |
| Features, settings, behaviour, mic protocol, tests to mirror | Starwire for Android (this repo) | The parity target |

Why not take VoidLink whole: it has 97k lines with no tests, files up to 7,800 lines, two settings
screens, one maintainer, and no upstream merges since Feb 2024. It also has none of Vibeshine's
extensions, and its DualSense haptics and mic use protocols Vibeshine doesn't speak. Taking it
whole would mean owning all of that. Picking its best files gives most of the benefit with code
we've read.

Why not the Codex Artemis port: see [Lessons](#lessons-from-the-codex-artemis-port). It is used
only as a list of what to avoid.

## What Vibeshine supports

Taken from Vibeshine `af1a0842` (2.0.1 plus nightlies, 22 Oct 2026). Line numbers refer to that
commit.

**The client should use:**
- Standard pairing and HTTPS (no OTP or per-client permissions, every paired client can launch
  and quit).
- Launch parameters:
  - `virtualDisplay=0/1`
  - `scaleFactor` (percent)
  - `clientVrrRequested=1` (VRR virtual display)
  - `clientName`
  - Fractional refresh rates in `mode` (`2388x1668x119.88`, or millihertz)
- `GET /bitrate?bitrate=<kbps>` mid-stream, clamped by the host. `/api/abr/capabilities` says the
  client runs its own adaptive bitrate.
- Synthetic Remote Monitor, Remote Input and Terminate tiles in the app list. Terminate answers
  HTTP 410 first and needs a second, confirmed request.
- `/power-actions/v1` to sleep the PC, if the host owner allows it for this client.
- `/api/hardware-metrics` for host CPU and GPU stats in the overlay. It is off by default on the
  host.
- PyroWave:
  - Advertised through server codec bits `0x00800000` to `0x04000000`.
  - `PYROWAVE/90000` in DESCRIBE, `bitStreamFormat=3`.
  - Record framing.
  - Optional link and pace hints.
  - A UDP calibration probe that runs only while no stream is active.
- HDR, YUV 4:4:4, AV1, HEVC.
- Rumble, trigger rumble, motion, LED, adaptive triggers.
- DualSense waveform haptics:
  - Control packet 0x5601.
  - Feature flag `0x04`.
  - Controller capability `0x8000`.
  - The PC side needs Vibeshine's "DualSense USB audio and haptics" component.
- Pacing from RTP timestamps, which follow the game's own presentation times. This is how
  Nonary's client paces VRR.

**Vibeshine does not have these, so they are dropped for this host:**
- Clipboard sync (`/actions/clipboard`).
- Server commands (serverinfo `ServerCommand`, control 0x3000).
- The in-stream microphone (`streamid=mic` gets a 404).
- MLCS clock sync, which Starwire's "host-timed" pacing uses. That mode is rebuilt on RTP
  timestamps instead.
- The client's FEC percentage request. FEC is set on the host (default 20%).
- Apollo per-client permissions.
- Pen barrel roll (VoidLink's packet 0x5500000B is ignored).

The client checks serverinfo for each of these, so they can be turned on later if Vibeshine or
another host adds them. Until then they aren't built or shown.

**The microphone** uses Starwire's own encrypted route (SWMC) to `StarwireMicReceiver` on the PC,
as it does on Android. It doesn't depend on the host at all. Plain VBAN is the fallback.

## Not possible on iOS

Only features that truly can't exist on iOS are listed. Everything else is built, sometimes in a
different way.

| Starwire for Android feature | Why not |
|---|---|
| Custom Vulkan driver (Turnip, libadrenotools) | iOS apps can't load GPU drivers, and the iPad GPU isn't Adreno |
| Raw USB driver for Xbox 360 / One controllers and the Xbox wireless dongle | iOS gives apps no raw USB access. Controllers iOS supports itself still work over Bluetooth or USB-C |
| Root evdev mouse capture | No root access on iOS |
| Vendor decoder low-latency flags (Qualcomm, Exynos, MediaTek, Amlogic) | Android hardware only. VideoToolbox's real-time mode is used instead |
| Audio effects toggle | iOS has no per-app system audio effects to turn off |
| "Sleep" as a custom command's last step | iOS apps can't lock or sleep the device |
| Android TV channels and poster provider | No Android TV home screen on iOS |
| Playing raw waveforms on the DualSense's actuators | iOS has no public API for it. Vibeshine's haptics are converted to Core Haptics patterns instead, as VoidLink does: close, not identical |
| Audio haptics on the iPad itself | iPads have no vibration motor. iPhone and controllers still get it |

**Needs the paid account, not impossible:** Wake-on-LAN. Broadcast packets need Apple's
multicast capability, which free accounts can't get and paid accounts must request. Without it,
the app shows a plain message instead of failing silently.

**Different on iOS, but built:**
- Launcher shortcuts become App Intents, the Shortcuts app and a `starwire://` URL scheme.
- The in-app language picker opens the app's language page in iOS Settings.
- Clipboard pasting shows iOS's paste prompt (only relevant if a host gains clipboard support).
- The stream stops in the background except in picture in picture.

## Architecture

```
ios/                          moonlight-ios history, kept mergeable
  Limelight/                  upstream core: Network, Crypto, Stream, Input. Small, marked edits
  Moonlight.xcodeproj         untouched (upstream merge target)
  moonlight-common/           builds Nonary's common-c (submodule)
  App/                        new: SwiftUI app, scenes, screens
  Stream/                     new: stream view controller, overlays, stream menu
  Video/                      Metal + AVSB renderers, pacing, PyroWave
  Audio/                      AudioUnit output, audio haptics, mic capture
  StarwireKit/                Swift package, no UIKit: settings, SWMC, VBAN, gestures,
                              shortcuts, pacing policy, stats, XML parsing. Tests run on
                              Windows, macOS and CI
  Tests/                      XCTest (app), snapshot tests, XCUITest smoke
  project.yml                 XcodeGen spec, generates Starwire.xcodeproj
docs/ios/                     this plan, the Mac runbook, device-run reports, measurements
```

- **Layers.** The UI talks to Swift protocols (`HostService`, `PairingService`, `StreamSession`,
  `InputSink`, `VideoSink`, `Clock`). Each has a real version over the ObjC core and a fake for
  tests and a demo mode. No test code inside production views.
- **Settings.** Typed Swift values, one store, with Android's keys and defaults so settings can be
  exported from Android and imported on iOS as JSON. Each game can override any setting. Short-
  lived state (keyboard shown, menu open) never goes into preferences.
- **Input.** UIKit for the stream surface (touch, Pencil, pointer, keyboard), GameController for
  pads, mice and keyboards. Held input is released only on disconnect, backgrounding, or the
  overlay that owns it closing. Fractional mouse movement is accumulated, never dropped. One
  function maps between the video and the screen for drawing, touch, Pencil and the pointer.
- **Video.**
  - `VTDecompressionSession` off the main thread.
  - Then either Metal (default: pacing, HDR with EDR, 4:4:4, overlays, PyroWave planes) or
    `AVSampleBufferDisplayLayer` (picture in picture).
  - Pacing runs on its own thread with `presentAfterMinimumDuration`, and the drawable's
    presented-time feedback drives the pacing modes.
- **PyroWave.** Themaister's decoder at `186f0393` with Granite, through MoltenVK, sharing R8/R16
  planes with Metal without copies, following Nonary's `pyrowavemetal.mm`.
- **Audio.** Opus multistream decoded as float32 into an AudioUnit (Andy's work), replacing SDL2.
  Stereo, 5.1 and 7.1, plus spatial audio without head tracking (head tracking needs a capability
  free accounts don't get).

## Lessons from the Codex Artemis port

| Avoid | Do instead |
|---|---|
| One global settings dictionary read by string key on every touch and frame | Typed settings, read once per session |
| A "settings changed" broadcast that releases all held keys and buttons | Targeted events |
| Saving short-lived UI state as preferences | Keep session state apart |
| Editors made of `UIAlertController` text prompts | Real editors: key grid, drag to move, handles to resize |
| A stream menu of chained action sheets, then "wait for dismissal" test fixes | A custom side panel |
| Test hooks and harness UI in production view controllers | Protocols and fakes |
| UI tests that read debug labels, sample pixels and sleep 5 to 15 s | Logic tests with injected time; few UI tests, waiting on conditions |
| Fixed `dispatch_after` delays and timers that run while their feature is off | System callbacks and state |
| Mouse deltas cast to `short`, remainder lost | Accumulate fractions |
| Hand-edited `project.pbxproj` | XcodeGen |
| Removing original authors' headers | Keep every header, credit every copied file |
| Feature lists claiming work never run on a device | A feature is done when the Mac run says so |

## How work moves between machines

1. **Windows PC (here):** write code; run StarwireKit tests with Swift for Windows (`swift test`,
   seconds); push a branch.
2. **GitHub Actions (`macos-26`, Xcode 26):** generate the project, build for the simulator in
   Debug and Release, run StarwireKit and XCTest unit tests, run snapshot and smoke tests, and
   upload the logs. The Android workflows skip changes that only touch `ios/`.
3. **M1 Mac (Claude Code there):** follow `docs/ios/mac-runbook.md`:
   1. Pull the branch.
   2. Build and sign with the free Apple ID.
   3. Install on the iPad with `xcrun devicectl`. Install over the old copy, never delete it,
      so pairing survives.
   4. Run the device tests and the live-host smoke tool against Vibeshine.
   5. Write a short report to `docs/ios/device-runs/<date>-<branch>.md` and push it.
4. **Back here:** read the report, fix, repeat. A feature is only marked done in the parity table
   once a device report shows it working.

The Mac needs macOS 15.6 or later and Xcode 26 or later, plus Homebrew, XcodeGen and Claude Code.
Phase 0 writes the exact steps.

## Signing and sideloading

- **Free Apple ID:**
  - The app runs for 7 days, then must be reinstalled from the Mac. Data and pairing survive a
    reinstall over the top.
  - At most 3 free-signed apps per device.
  - No multicast (Wake-on-LAN), no head-tracked spatial audio.
  - Andy's branch requests restricted capabilities and a fixed team ID. Both are removed in
    phase 0.
- **Paid work account:** a 1-year install, and Wake-on-LAN after Apple approves the multicast
  request. Check your employer's policy before signing personal apps with a work account.
- **Bundle ID:** `io.github.shev0k.starwire` unless you choose another.

## Phases

Each phase lists what you'll see, which tests prove it, and which docs change. Sizes are relative:
S, M, L, XL.

### Phase 0: groundwork (M)
Goal: an iPad build that streams from Vibeshine, before any new features.
- Bring moonlight-ios into `ios/` with `git subtree add`, keeping its history. Merge Andy's
  `andyg.ios-metal-squash` the same way, using the conflict resolutions from the research. Fix
  the duplicate `LSSupportsGameMode` key. Remove the restricted capabilities and the hard-coded
  team.
- Switch common-c to Nonary's fork at a pinned commit. Add its new files to the build. Set up the
  imgui and implot submodules.
- Write `project.yml` for one iPhone and iPad target on iOS 17. Leave upstream's project and tvOS
  target alone.
- Set up CI (`ios.yml`), and add a path filter so the Android CI skips iOS-only changes.
- Write `docs/ios/mac-runbook.md` and the device-run report template.
- Create the StarwireKit skeleton with `swift test` passing on Windows and CI.
- **Done when:**
  - CI is green.
  - The Mac installs the app on the iPad.
  - The upstream UI pairs with Vibeshine and streams Desktop with HEVC at 120 Hz through the Metal
    renderer.
  - A device report records frame rate and drops.

### Phase 1: core stability (L)
- Stream start and stop race fixes (from daniel-zn), the UIScene lifecycle, and the client key
  and certificate moved into the Keychain.
- Metal renderer fixes:
  - Unsafe log formats.
  - A possible deadlock on shutdown.
  - The per-frame `waitUntilCompleted` stall.
  - Nil guards and teardown from VoidLink.
  - VoidLink's working EDR path.
- The Swift protocol seams with fakes, and a demo mode built on the fakes.
- StarwireKit settings: every Android key and default, per-game overrides, JSON import and export.
- Pairing: PIN flow, the Vibepollo/Vibeshine pair-state debounce, pinned-certificate refusal grace
  with an injected clock, and MAC preservation.
- **Done when:**
  - Unit tests pass for settings, migration and pair state. Recorded Vibeshine XML fixtures parse.
  - On the iPad: pair, stream 10 times in a row, and background and resume the app, all with no
    crash or stuck session.

### Phase 2: Vibeshine features (M)
- Launch options:
  - virtual display on, off or host default
  - `scaleFactor`
  - VRR request
  - fractional and ProMotion refresh rates
  - `clientName`
- Bitrate changes mid-stream from the stream menu.
- Remote Monitor, Remote Input and Terminate tiles, with the confirmation step.
- Sleep the PC through power actions.
- Host CPU and GPU in the overlay through hardware metrics.
- Parsing of serverinfo extras (VirtualDisplayCapable, HDRCapable, PyroWave fields).
- **Done when:**
  - Fixture tests cover each endpoint and the 410 retry.
  - On the iPad: launch into a 2388x1668 virtual display at 120 Hz, change bitrate during a game,
    terminate with confirmation, sleep the PC.

### Phase 3: the app (L)
Can run alongside phases 4 to 6.
- The SwiftUI app, replacing upstream's storyboards (which stay in the tree, unused):
  - PC list with frosted cards.
  - Game screen hero with cover colours, generated tiles and icon tiles.
  - Quick Launch.
  - The overrides bar.
  - App menu: virtual or primary display, per-game settings, hide app, details.
  - Settings with section pills, plain names, impact lines, the predicted-impact panel on the iPad,
    and credits.
  - About and licences.
- Layouts for iPad (Split View, Stage Manager) and iPhone.
- VoiceOver, Dynamic Type, Reduce Motion.
- The 33 translations, converted from `strings.xml` by a script.
- Controller navigation of every screen.
- **Done when:** snapshot tests pass for each screen on iPhone and iPad, in light and dark, at
  normal and largest text. A device report covers VoiceOver and controller navigation.

### Phase 4: video and pacing (XL)
- Metal as the default renderer, and AVSB for picture in picture.
- HDR10 with EDR, full range, YUV 4:4:4.
- AV1 on devices with hardware AV1 (M4 iPad Pro, A17 Pro and later). Older chips fall back to
  HEVC, because software AV1 can't keep up at these rates.
- Starwire's pacing modes:

  | Mode | On iOS |
  |---|---|
  | Latency, Balanced, Cap FPS, Smoothness | Rebuilt on the Metal presenter |
  | Host-timed | Paced from RTP timestamps, as Nonary's client does |
  | Warp, Warp2 | Ask for 2x or 4x FPS and show the newest frame |
  | VRR | ProMotion with `clientVrrRequested` |

- Jitter buffer presets, V-Sync options where they apply, reduce refresh rate, measured refresh.
- Full and Lite overlays: bandwidth, ping, decode time, drops, FPS, 1% low, received and rendered
  FPS, host hardware metrics. Optional ImGui graphs.
- Picture in picture, external display (mirror or extended through UIScene), rotate, brightness
  slider, stretch video.
- Frame interpolation on iOS 26, as an option.
- Post-stream latency summary.
- **Done when:**
  - Pacing policy unit tests pass (porting Starwire's pacer tests where the logic carries over).
  - The live-host smoke tool records 10-minute runs per mode into `docs/measurements/ios/`.
  - The README claims only modes that were measured.

### Phase 5: input (XL)
- Touch modes:
  - multi-touch passthrough
  - direct
  - natural trackpad
  - gaming trackpad
  - disabled
  - swapped clicks
- Long-press right click, sensitivity, pinch to zoom, and pan and zoom mode.
- Apple Pencil with VoidLink's pressure curves (hover where supported).
- On-screen controller with a real layout editor, L3/R3-only and Guide options, opacity and
  vibration.
- The 82-key keyboard with sticky modifiers. Text input through the system keyboard.
- Shortcuts:
  - the 14 built in
  - imported shortcut files (Starwire's JSON format, through the Files app)
  - custom commands with close, disconnect or quit after
  - monitor switching (Ctrl+Alt+Shift+F1 to F6)
  - hide PC cursor with its crash-safe ledger
- The stream menu: a side panel opened by the floating button, a three-finger tap, or holding a
  controller button. It has every tool from Android that this host supports.
- Gamepads:
  - multiple controllers, deadzone, flip face buttons, analog scrolling
  - mouse emulation
  - touchpad as mouse
  - motion, with the device gyro as fallback
  - rumble, trigger rumble, adaptive triggers, LED, battery
  - vibration fallback
  - Vibeshine's 0x5601 DualSense haptics as Core Haptics patterns
  - the system Home-button gesture disabled while streaming
- Hardware keyboard and mouse: pointer lock on iPad in full screen, back and forward buttons,
  high-resolution scroll.
- **Done when:**
  - Recording-sink tests assert the exact packets for every gesture, control and shortcut.
  - Gesture state machines are tested with injected time.
  - A device report covers the DualSense, the FlyDigi Apex 5, the phone grip, a keyboard, a mouse
    and the Pencil. The Apex 5 is checked first for the mode it shows up in on iOS.

### Phase 6: audio and microphone (L)
- AudioUnit output: stereo, 5.1 and 7.1, spatial audio, audio session handling (calls, route
  changes, AirPods).
- Audio haptics:
  - From the game's bass, as on Android.
  - To the iPhone's Taptic Engine, or the controller's motors.
  - Strength 25 to 200%.
- Microphone, using Starwire's SWMC protocol:
  - Pairing with the 16-character code.
  - Keys kept in the Keychain.
  - Capture through `AVAudioEngine` with Apple's echo and noise cancelling.
  - 48 kHz mono in 256-sample VBAN packets.
  - AES-256-GCM.
  - Every timing and retry rule from `docs/dev/mic-protocol.md`.
- Plain VBAN as the fallback.
- Microphone device selection where iOS offers several (built-in, headset, USB).
- **Done when:**
  - StarwireKit passes the same `swmc-v1-vectors.txt` as Android and Windows.
  - A loopback test runs against `StarwireMicReceiver` on a temporary port on the PC.
  - Your voice is heard in a game on the PC.
  - A security review pass is written up, and you sign it off.

### Phase 7: PyroWave (L, the least certain, done last)
The iPad is on Wi-Fi only, and PyroWave wants 200 Mbit/s or more, ideally wired. So this phase
comes after phase 8. It stays in the plan because Wi-Fi 6E or a later wired setup may make it
usable.
- Bring in PyroWave `186f0393`, Granite, MoltenVK (iOS build) and Nonary's patches, including the
  macOS portability patch. Port `pyrowavemetal.mm`, the framing, and the calibration flow.
  Nonary's common-c already handles the protocol side.
- First a 2-day trial on the iPad: can an M1 decode 1440p and 4K at 120 FPS within budget? The
  calibration tool answers this.
- Late-frame presets as on Android (off to smoothest).
- **Done when:** a calibrated PyroWave stream runs over USB-C Ethernet or fast Wi-Fi with
  measurements. Otherwise, the README states the limits found.

### Phase 8: stability, polish and docs (M)
- 1-hour soak streams, leak checks in Instruments, MetricKit crash logs kept on the device.
- iOS 17 checked on the simulator, since the test devices run newer versions.
- App Intents and the `starwire://` URL scheme: start a game, quit the stream.
- README iOS section, CHANGELOG, and "Where every feature comes from" with credits for every
  copied file.
- **Done when:** a final device report covers the whole parity table, and the README matches it.

## Parity tracking

`docs/ios/parity.md` (made in phase 0) lists every Android feature and setting key, its phase,
and its status:
- **planned**
- **built:** CI green
- **verified:** a device report links to it
- **not possible:** from the list above
- **host lacks it:** Vibeshine

Only "verified" counts as done.

## Risks

- **PyroWave on iPad:** the M1 may not decode high resolutions at 120 FPS. The trial comes before
  any polish.
- **Free signing:** weekly reinstalls. If they become a chore, the paid account solves it.
- **No devices in CI:** pacing, HDR, haptics and the mic can only be checked on the Mac runs.
- **Upstream drift:** Nonary's common-c moves fast. Pin a commit and update deliberately.
- **Two different common-c forks:** Android uses Starwire's common-c and iOS uses Nonary's, so
  protocol fixes have to be carried by hand between them.
- **iPhone:** it gets every feature, but with no iPhone to test on, layouts, the Taptic Engine and
  audio haptics on the phone are checked on the simulator only.

## Side note for Android

Starwire for Android's `callbacks.c` leaves `fecPercentage` at 0, so it asks hosts for no FEC.
Vibeshine ignores that request, so your setup isn't affected. A separate session can fix it for
other hosts. Android's PyroWave is also at a different commit (`89f7e47`) from Vibeshine
(`186f0393`), and the bitstream has no version check, so it is worth testing before relying on
PyroWave on Android with Vibeshine.
