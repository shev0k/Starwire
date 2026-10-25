# Mac runbook: build, sign and test Starwire on the iPad

Steps for Claude Code (or a person) on the owner's M1 Mac. The Windows PC writes the code and
GitHub Actions builds it for the simulator; this Mac is the only place the app is signed,
installed on the iPad and tested against the PC. The plan is [port-plan.md](port-plan.md).

Written 25 Oct 2026, before any of it was run on the Mac. Fixed after the first run
([device-runs/2026-10-24-feature-ios-phase-0.md](device-runs/2026-10-24-feature-ios-phase-0.md))
the phase 1a run
([device-runs/2026-10-25-feature-ios-phase-1a.md](device-runs/2026-10-25-feature-ios-phase-1a.md))
and the pacing run
([device-runs/2026-10-25-feature-ios-pacing.md](device-runs/2026-10-25-feature-ios-pacing.md)).
When a run shows something else wrong here, fix this page in the same branch as that run's report.

## Running it all from the PC (`ios/scripts/mac.sh`)

Since batch 1 (25 Oct 2026) one agent on the Windows PC runs the whole loop over SSH, so nobody
carries prompts to the Mac. The sections below are what the script does, for reference and for a
person at the Mac.

```bash
ios/scripts/mac.sh setup                 # once: the agent's own checkout, ~/Developer/Starwire
ios/scripts/mac.sh sync                  # push this branch, pull it on the Mac with the submodules
ios/scripts/mac.sh sync --wip            # the same, plus uncommitted changes under ios/
ios/scripts/mac.sh build                 # Release build of the app and the device-run tests
ios/scripts/mac.sh install               # over the old copy; never uninstalls
ios/scripts/mac.sh unit                  # unit tests on a simulator
ios/scripts/mac.sh test stream PRESENTER=display JITTER_BUFFER=balanced SECONDS=120
ios/scripts/mac.sh log 20                # start the app with its console log for 20 seconds
```

`test` takes `stream`, `resume`, `streams` or a test method name such as `testPictureInPicture`;
each `VAR=value` becomes `TEST_RUNNER_STARWIRE_VAR`. The `[device-run]` lines come back to
`build/mac/` on the PC. Batch 2 added `testBitrateChange`, `testRemoteInput`, `testRemoteMonitor`
and `testDemoMode`, and the variables `DISPLAY_MODE`, `SCALE`, `EXACT_FPS`, `VRR` and `BITRATES`
(listed at the top of `ios/Tests/DeviceRun/StreamDeviceRunTests.swift`).

`unit` signs the simulator build ad hoc (`CODE_SIGN_IDENTITY=-`, no certificate needed): an
unsigned app gets no Keychain on the simulator (error -34018), and the identity tests need it.

`mac.sh sync` pushes the branch to GitHub, which is public. Check what it would publish first:
no addresses, MACs, host IDs, keys or values that look like keys, even made-up ones in tests (a
secret scanner flagged a made-up token in a fixture on 25 Oct 2026).

What it needs on the Mac:
- The SSH key `~/.ssh/id_ed25519_starwire_mac` on the PC, the Mac's `user@host` in `~/.config/starwire/mac-host`
  on the PC (or `STARWIRE_MAC`), and Remote Login on the Mac. The address stays out of git.
- `~/.config/starwire/env` with `STARWIRE_TEAM=<team ID>` (section 3). Optionally `IPAD=<UDID>`;
  otherwise the first connected iPad is used. This file stays out of git.
- Someone logged in at the Mac. Codesign can't use the login keychain from SSH (it fails with
  `errSecInternalComponent`), so `build` runs as a one-off launchd job in the logged-in session,
  as self-hosted CI runners do, and removes it afterwards. The Mac's password is never needed.
  Such jobs can't read `~/Documents`, which is why the script has its own checkout in
  `~/Developer/Starwire`. The copy in `~/Documents` is left alone.
- The Mac awake. Its power settings say `sleep 1` (asleep after a minute idle), and on 25 Oct
  2026 SSH dropped mid-batch when it dozed between runs. Builds and tests run under `caffeinate`;
  before a long batch also start `nohup caffeinate -dims -t 10800 &` on the Mac, which changes no
  setting and ends on its own. `test` runs detached and is polled, so a dropped connection doesn't
  stop it.

The PC is also the Vibeshine host, and the owner may be using it during a run. Its app list has
"Starwire test pattern", which runs `ios/scripts/test-pattern.ps1` (installed in
`%LOCALAPPDATA%\StarwireTestPattern`): testufo.com full screen in a Chrome kiosk window with its own
empty profile, on the stream's own virtual display. The app's entry sets
`"virtual-display-layout": "extended_isolated"`, so the PC's monitors stay on (Vibeshine's default
layout, `exclusive`, turns them off for every stream), and the device tests pass
`-StarwirePlayAudioOnPC YES` so the PC keeps its sound. Other apps keep the host's defaults. A
second app, "Starwire colour bars", shows `ios/scripts/colour-bars.html` the same way, for colour
checks: run `test stream "APP=Starwire colour bars" FRESH=1` (add `AVSB=1` for the system's video
layer instead of Metal), export the screenshots with `xcrun xcresulttool export attachments`, and
measure them with `swift ios/scripts/colour-bars.swift <png>`. It
was added on 25 Oct 2026 with the owner's OK; `apps.json` was backed up next to itself first.

## Rules for every run

- **Never delete the app from the iPad.** Not with `devicectl`, not from the home screen. Always
  install over the old copy. Deleting it loses the pairing with the PC, and pairing again needs
  the PC.
- Keep the bundle ID and the team the same from run to run, for the same reason.
- Don't commit anything signed, any provisioning profile, or the team ID. Only the report goes
  into git.
- Claim only what you saw. If a step was skipped or failed, the report says so.

## What the Mac needs

| What | Version | Check with |
| --- | --- | --- |
| macOS | 15.6 or later (first run: 27.0.1) | `sw_vers` |
| Xcode, with the iOS platform | 26 or later (first run: 27.0) | `xcodebuild -version` and `xcodebuild -showsdks` (lists `iphoneos`) |
| Metal Toolchain | same build as Xcode | `xcodebuild -showComponent MetalToolchain` says `Status: installed` |
| Homebrew | any, optional | `brew --version` |
| XcodeGen | any recent (first run: 2.46.0) | `xcodegen --version` |
| git | any | `git --version` |
| Claude Code | any | |

```bash
brew install xcodegen
xcodebuild -downloadPlatform iOS   # only if xcodebuild -showsdks lists no iphoneos
xcodebuild -downloadComponent MetalToolchain   # about 840 MB; without it the device build fails
```

In Xcode 27 the Metal shader compiler is a separate download. Without it the build stops with
`cannot execute tool 'metal' due to missing Metal Toolchain`.

Without Homebrew, build XcodeGen from source (about a minute on an M1, no admin password):

```bash
git clone --depth 1 --branch 2.46.0 https://github.com/yonaskolb/XcodeGen.git /tmp/XcodeGen
swift build -c release --package-path /tmp/XcodeGen --disable-sandbox
mkdir -p ~/.local/share/xcodegen ~/.local/bin
cp /tmp/XcodeGen/.build/release/xcodegen ~/.local/share/xcodegen/
cp -R /tmp/XcodeGen/.build/release/XcodeGen_XcodeGenKit.bundle /tmp/XcodeGen/SettingPresets ~/.local/share/xcodegen/
ln -sf ~/.local/share/xcodegen/xcodegen ~/.local/bin/xcodegen
export PATH="$HOME/.local/bin:$PATH"
```

The iPad:
- iPad Pro with an M1 or newer, iPadOS 17 or later.
- Developer Mode on: Settings > Privacy & Security > Developer Mode, then restart.
- Connected to the Mac with USB-C the first time, unlocked, and "Trust This Computer" accepted.
  Later runs also work over the same Wi-Fi once Xcode has seen the iPad.

The PC: Vibeshine running, on the same network as the iPad.

## 1. Get the code

First time:

```bash
git clone https://github.com/shev0k/Starwire.git
cd Starwire
```

Every later run, with the branch the PC session named (for example `feature/ios-phase-0`):

```bash
git fetch origin
git checkout feature/ios-phase-0
git pull --ff-only
```

Then the iOS submodules only (Android's aren't needed on the Mac). `sync` first picks up a
submodule whose address moved in `.gitmodules` (common-c moved to `shev0k/moonlight-common-c` in
phase 1a):

```bash
git submodule sync --recursive
git submodule update --init --recursive ios/moonlight-common/moonlight-common-c ios/X1Kit ios/third_party/imgui ios/third_party/implot
```

## 2. Generate the Xcode project

```bash
cd ios
xcodegen generate
```

This writes `ios/Starwire.xcodeproj`, which git ignores. Run it again after every pull. Don't
open or change upstream's `Moonlight.xcodeproj`.

## 3. Sign with the free Apple ID

Once per Mac:
1. Open Xcode > Settings > Accounts, press +, and sign in with the free Apple ID. Xcode makes a
   "Personal Team" for it.
2. Find the team ID (10 characters):

   ```bash
   defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier
   ```

   Use the `teamID` of the entry with `isFreeProvisioningTeam = 1`. If Xcode has more than one
   Apple ID, there is one such entry for each; pick the one whose `teamName` is the owner's. If
   that key doesn't exist, try `defaults read com.apple.dt.Xcode IDEProvisioningTeams`, or select the team in a project's
   Signing & Capabilities tab, where Xcode shows it.
3. Keep it in the shell, never in a committed file:

   ```bash
   export STARWIRE_TEAM=XXXXXXXXXX
   ```

The bundle ID is `io.github.shev0k.starwire`. A free account needs it to be unused by every
other Apple developer. If the build says the ID can't be registered, add
`PRODUCT_BUNDLE_IDENTIFIER=io.github.shev0k.starwire.ipad` to the build command, write that ID in
the report, and use the same one on every later run.

What a free account means:
- The app runs for 7 days, then has to be installed again from the Mac. Installing over the old
  copy keeps its data and pairing.
- At most 3 apps signed this way on the iPad at once.
- No Wake-on-LAN and no head-tracked spatial audio (they need capabilities free accounts can't
  get).

## 4. Build for the iPad

Find the iPad's identifier:

```bash
xcrun devicectl list devices
```

```bash
export IPAD=<identifier from the list>
```

Build Release for stream tests (Debug turns optimisation off, so its frame times aren't
representative), from `ios/`:

```bash
xcodebuild -project Starwire.xcodeproj -scheme Starwire -configuration Release -destination "generic/platform=iOS" -derivedDataPath ../build/DerivedData -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM="$STARWIRE_TEAM" CODE_SIGN_STYLE=Automatic build 2>&1 | tee ../build/device-build.log
```

`-allowProvisioningDeviceRegistration` registers the iPad with the personal team if it isn't
yet. If signing still says no device is registered, build once with
`-destination "platform=iOS,name=<the iPad's name>"` instead, with the iPad connected and
unlocked. The app ends up in `../build/DerivedData/Build/Products/Release-iphoneos/Starwire.app`.

## 5. Install over the old copy

```bash
xcrun devicectl device install app --device "$IPAD" ../build/DerivedData/Build/Products/Release-iphoneos/Starwire.app
```

This replaces the app and keeps its data. Never run `devicectl device uninstall`.

The first time only, iPadOS asks you to trust the developer: Settings > General > VPN & Device
Management > the Apple ID > Trust. Until then, launching fails with "its profile has not been
explicitly trusted by the user". On its first start the app also asks for Local Network access:
tap Allow, or it can't find the PC.

Start it from the Mac, with its log in the terminal and in a file:

```bash
xcrun devicectl device process launch --console --terminate-existing --environment-variables '{"OS_ACTIVITY_DT_MODE":"enable"}' --device "$IPAD" io.github.shev0k.starwire 2>&1 | tee ../build/device-run.log
```

Without `OS_ACTIVITY_DT_MODE`, `--console` shows nothing, because the app logs through the system
log. The log stops when the app is closed on the iPad; a copy started from the home screen isn't
logged this way (see "Reading the app's log" below for that).

### Reading the app's log

From `feature/ios-phase-1a` on, Release builds log too. Every line is in the unified log under
the subsystem `io.github.shev0k.starwire`, with one category per area: `app`, `stream`, `video`,
`pacing`, `network`, `input` and `audio`. Extra detail (LOG_D lines) needs "Verbose logging" on in
iOS Settings > Apps > Starwire, and a restart of the app.

- While the app runs from `devicectl ... --console` (above), its lines are in the terminal.
- For a run started any other way (from the home screen, or by `xcodebuild test`), collect the
  iPad's log afterwards and filter it. `log collect` from an attached device needs root, so it
  needs the Mac's admin password (without `sudo` it stops with "Must be root"). In zsh, `log` is
  a shell built-in, so call `/usr/bin/log`:

  ```bash
  sudo /usr/bin/log collect --device-udid "$IPAD_UDID" --last 30m --output ../build/ipad.logarchive
  /usr/bin/log show ../build/ipad.logarchive --style compact --predicate 'subsystem == "io.github.shev0k.starwire"' > ../build/app-log.txt
  grep "pacing window" ../build/app-log.txt
  ```

  `$IPAD_UDID` is the iPad's UDID (`xcrun xctrace list devices` shows it in brackets). With
  Xcode 27 `devicectl list devices` printed the UDID as the identifier, so the two were the same.
  If `log collect` can't be run, say so in the report; the overlay samples carry the short pacing
  line, but not the full `pacing window` lines.

Logs never contain the pairing PIN or the stream's input key (`rikey` is shown as
`<redacted>`). They do contain the PC's addresses: remove those before quoting lines in a report.

Signposts for Instruments (decode, enqueue, drop and present) are in the `pacing` category, for
when a run needs a timeline: Instruments > Logging > os_signpost, recording the iPad.

## 6. Run the tests

StarwireKit, the Swift package with no UIKit:

```bash
swift test --package-path StarwireKit 2>&1 | tee ../build/starwirekit-tests.log
```

The same simulator build as CI, to tell a Mac-only problem from a code problem:

```bash
xcodebuild -project Starwire.xcodeproj -scheme Starwire -configuration Debug -destination "generic/platform=iOS Simulator" -derivedDataPath ../build/DerivedData CODE_SIGNING_ALLOWED=NO build 2>&1 | tee ../build/simulator-build.log
```

The app's unit tests (`StarwireTests`), the same ones CI runs. They need a simulator, not the iPad:

```bash
xcrun simctl list devices available | grep -E "iPad|iPhone" | head
xcodebuild -project Starwire.xcodeproj -scheme Starwire -configuration Debug -destination "platform=iOS Simulator,name=<a name from the list>" -derivedDataPath ../build/DerivedData CODE_SIGNING_ALLOWED=NO test 2>&1 | tee ../build/unit-tests.log
grep -E "Executed [0-9]+ tests|error: -\[" ../build/unit-tests.log
```

### The device-run UI tests

`StarwireDeviceRun` (in `ios/Tests/DeviceRun`) drives the app on the iPad against the PC, so nobody
has to sit at the iPad. It needs the PC awake and paired, and Statistics Overlay on in the app's
settings. It has three tests:

| Test | What it does |
| --- | --- |
| `testStreamAndSample` | Starts the app tile, reads the statistics overlay every 15 seconds for `STARWIRE_SECONDS` (default 300), takes screenshots at the start and end, records the "Pacing summary" line at the end, stops with an edge swipe, and checks the app list is back with no alert |
| `testBackgroundAndResume` | Starts a stream, switches to the Settings app for 10 seconds, comes back, checks the app list is showing with no alert, then streams and stops once more |
| `testStreamsInARow` | Starts and stops `STARWIRE_STREAMS` streams (default 10), 10 seconds each, checking for an alert and that the app is still running after each |

Options are environment variables with a `TEST_RUNNER_` prefix, which `xcodebuild` passes to the
test. The test turns them into the app's launch arguments; the app has no code for tests.

| Variable | Values |
| --- | --- |
| `TEST_RUNNER_STARWIRE_APP` | app tile to start, default `Desktop` |
| `TEST_RUNNER_STARWIRE_SECONDS` | stream length for `testStreamAndSample` |
| `TEST_RUNNER_STARWIRE_STREAMS` | streams for `testStreamsInARow` |
| `TEST_RUNNER_STARWIRE_PRESENTER` | `loop` (default, the render loop) or `display` (CAMetalDisplayLink) |
| `TEST_RUNNER_STARWIRE_PRESENT_TIMING` | `nearest` (default) or `frame` (the old rule) |
| `TEST_RUNNER_STARWIRE_DROP_POLICY` | `alternate` (default, the old one) or `newest` |
| `TEST_RUNNER_STARWIRE_BUFFER` | frames to buffer, `1` to `3`; unset uses the app's setting |
| `TEST_RUNNER_STARWIRE_VIRTUAL_DISPLAY` | `1` to stream a Vibeshine virtual display |

One run, from `ios/`:

```bash
TEST_RUNNER_STARWIRE_PRESENT_TIMING=nearest xcodebuild test -project Starwire.xcodeproj -scheme StarwireDeviceRun -configuration Release -destination "id=$IPAD_UDID" -derivedDataPath ../build/DerivedData -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM="$STARWIRE_TEAM" CODE_SIGN_STYLE=Automatic -resultBundlePath ../build/run-B.xcresult -only-testing:StarwireDeviceRun/StreamDeviceRunTests/testStreamAndSample 2>&1 | tee ../build/run-B.log
grep -A8 "\[device-run\]" ../build/run-B.log
```

- `xcodebuild test` installs the app over the old copy, which keeps the pairing. It also installs
  the test runner (`io.github.shev0k.starwire.devicerun.xctrunner`), a second free-signed app.
  A free account allows 3 such apps on the iPad. If the install fails with "reached the maximum
  number of installed apps using a free developer profile", the error lists them. The phase 0
  runner (`io.github.shev0k.starwire.uitests.xctrunner`) isn't needed any more and can go, with
  the owner's OK: `xcrun devicectl device uninstall app --device "$IPAD"
  io.github.shev0k.starwire.uitests.xctrunner`. Never uninstall `io.github.shev0k.starwire`.
- After the first run, use `test-without-building` instead of `test` with the same options: it
  skips the build and install, which saves about half a minute per run.
- A result bundle path must be new for each run: delete the old `.xcresult` or use a new name.
- The overlay samples are the `[device-run]` lines in the log, and attachments in the result
  bundle (`open ../build/run-B.xcresult`).
- The sample at 0 s is taken the moment the overlay appears, before the stream settles (15 to
  110 FPS, decode max near 30 ms). Leave it out of means.
- On the iPad Pro, `XCUIDevice.shared.press(.home)` didn't send the app to the background in the
  first run; activating the Settings app does, which is what the test uses.

## 7. The device checks for this phase

Phase 0 is done when the iPad pairs with Vibeshine and streams the Desktop with HEVC at 120 Hz
through the Metal renderer. In the app (upstream's screens for now):

1. Add the PC if it isn't listed. Pairing shows a PIN: enter it in Vibeshine's web UI on the PC.
2. In Settings: Resolution to the iPad's native resolution (or the closest one offered; "Safe
   Area" gave 2420x1668 on an 11-inch iPad Pro), Frame Rate 120 FPS, Preferred Codec HEVC,
   Statistics Overlay on. Write down the bitrate it shows.
3. Open https://www.testufo.com (or a video at 60 fps or more) on the PC's streamed screen and
   leave it running. The host only sends frames when the picture changes, so a still desktop shows
   about 15 FPS and says nothing about 120 Hz. Start Desktop. Stream for at least 5 minutes, counted
   from when the picture appears, not from the tap.
4. Take screenshots of the statistics overlay at the start and near the end (top button + volume
   up). Note frame rate, dropped frames, decode time and network latency from it.
5. Background the app, come back, and stop the stream (swipe in from the left edge). Note any
   crash or hang. Going to the background ends the stream on purpose (`applicationDidEnterBackground`
   in `StreamFrameViewController.m`), so coming back should show the app list.

The overlay's FPS is frames shown: frames received minus network drops minus pacing drops
(`getStatsOverlayText` in `StreamManager.m`). To get the frames received, divide by
(1 - pacing drops).

These checks can be run without anyone at the iPad by the device-run UI tests (section 6). The
first run used a local copy of them (`ios/devicerun.yml`); from `feature/ios-phase-1a` they are in
git, so that local spec isn't needed any more.

The renderer in this build is Andy Grundman's Metal one (it replaced upstream's
`AVSampleBufferDisplayLayer` renderer), so a working stream is a working Metal path.

## 7a. Pacing checks (`feature/ios-phase-1a`, `feature/ios-pacing`)

Pacing is done when, on the iPad:
- pacing drops are under 1% at 120 FPS with moving content, with no more decode to screen
  latency than the render loop has, or the report explains with measurements why not and names
  the next step;
- 10 streams in a row, plus background and resume, end with no crash and no double alert;
- the PC shows as online (serverinfo works over the network);
- the app's own log lines are readable from a Release build.

### What phase 1a found

At 2420x1668, 120 FPS, HEVC with testufo.com moving, every setting tried dropped about 12% of
frames: the old and new present timing, both drop policies, and buffers of 2 and 3 (see
[the phase 1a report](device-runs/2026-10-25-feature-ios-phase-1a.md)). Network drops were 0%,
bursts were 0%, the frame queue sat near 1.9 of 2, and about 105 FPS were shown. So the app takes
frames off the queue more slowly than they arrive, at every setting.

Its "held 2+ refreshes" counter said only 1.9%. That counter put any interval under 1.5 refreshes
in "one refresh", and 1.5 refreshes at 120 Hz is exactly 12.5 ms. A ProMotion panel can show a
frame on a 4.17 ms grid, so a frame that misses its refresh may stay up 12.5 ms, not 16.7 ms,
and the counter could miss it. About a quarter of frames at 12.5 ms would give the 105 FPS seen.
That is the theory this branch measures.

### What `feature/ios-pacing` adds

**Measurement.** Every frame's time on screen comes from the drawable's `presentedTime`, sorted
into half-refresh steps, and the display's refresh interval comes from the display link. The
overlay's last three lines:

```
Pacing: bursts x%, drops after burst n, skipped n, late n
Shown for 4.2/8.3/12.5/16.7/20.8/25+ ms: a/b/c/d/e/f%, mean m ms, refresh r ms, decode to screen l ms
Pacing summary (loop): 120 s, in 14400, drops x% (incoming n, oldest n, replaced n), arrival late n, gaps n, max gap g ms; shown n, shown for ..., mean m ms, max s ms, ...
```

The first two cover the last 5 second window. The summary line covers the whole stream so far
(whole 5 second windows plus the current one), and `testStreamAndSample` records it at the end as
a `[device-run] summary:` line, so no `log collect` is needed. The log's `pacing window` lines have
everything, including the refresh histogram.

| Field | Meaning |
| --- | --- |
| Shown for | How long each frame stayed on screen. At 120 FPS on 120 Hz it should be nearly all 8.3 ms |
| mean (shown) | The mean of those times. 8.33 ms is 120 FPS on screen; 9.4 ms is about 106 |
| max (shown) | The longest a frame stayed up: the worst freeze |
| arrival late, gaps, max gap | Decoded frames that came 1.5 to 2.5 frames after the one before (late), or more than 2.5 frames after it (gaps), and the longest gap. Measured as frames leave the decoder, before either presenter |
| refresh | The display's refresh interval while streaming, from the display link. 8.33 ms is 120 Hz |
| off grid | Times more than a quarter step off the 4.17 ms grid: the panel isn't on a fixed grid |
| late | Display presenter only: frames shown more than half a step after the refresh they were drawn for |
| skipped | Drawables the compositor never showed |
| replaced | Display presenter only: frames skipped because a newer one was waiting at a refresh |
| refreshes without a new frame | Display presenter only: refreshes where no new frame had arrived, so the last one stayed up |
| drawable wait | Render loop only: time spent waiting in `nextDrawable` |
| decode to screen | From the end of decoding to `presentedTime`: queue, render and compositor together. Compare it between presenters for latency |
| Network: gaps, max | From batch 1. Frames whose last packet came more than 2.5 frame intervals after the one before, timed from the packets (`DECODE_UNIT` receive and enqueue times), before any decoding. The first gap of a stream is the start, not a fault |
| every n ms (r% regular) | The median time between network gaps over the stream, and the share of gaps on 1 to 4 times that period. A steady period means something on a timer, like the Wi-Fi radio leaving the channel |
| clumped, max clump | Frames that came within half a frame interval of the one before: what arrives after a hole |
| receive | Mean and longest time from a frame's first packet to its last |
| host gaps | Gaps in the host's own frame times. A host gap with a network gap means the host sent nothing; a network gap alone means the network held frames up |
| network to screen | From a frame's last packet to `presentedTime`: everything on the iPad |
| jitter buffer, held | Display presenter: the mode, and the mean and largest number of frames held back. "catch up" counts frames dropped to get back to the target |
| 1% low | The frame rate of the slowest 1% of on-screen frame times in a 5 second window; the summary keeps the worst window |

**The display presenter** (`StarwirePresenter`, "Presenter" in iOS Settings > Apps > Starwire, or
`TEST_RUNNER_STARWIRE_PRESENTER`). `loop` is the render loop from phase 1a and is still the
default. `display` drives drawing from a `CAMetalDisplayLink` at the stream's frame rate on the
render thread: at each refresh it takes the newest decoded frame (waiting at most half the time
left before the drawable is due), drops any older ones as "replaced", and presents the link's
drawable with no minimum duration. A refresh with no new frame draws nothing. It keeps no extra
frame: a frame is drawn at the next display link call after it arrives and shown one refresh
later. The present timing, drop policy and frames to buffer settings only affect the render
loop.

### Reading the numbers

| What the numbers show | What it means |
| --- | --- |
| Loop: refresh 8.33 ms, many frames shown for 12.5 ms, drawable wait near 8 ms or more | The theory holds: the render loop waits on drawables and its frames miss refreshes by half a refresh. The display presenter should fix it |
| Refresh mean above 8.33 ms, or off grid | The display isn't running a steady 120 Hz while streaming. Check Low Power Mode and Settings > Accessibility > Motion > Limit Frame Rate, and say what they were |
| Display: drops under 1%, shown for nearly all 8.3 ms, decode to screen no higher than the loop's | Fixed |
| Display: "replaced" and "refreshes without a new frame" both high, about equal | Frames arrive unevenly against the refresh: one refresh gets none, the next gets two. The host or Wi-Fi is uneven; try the virtual display run, and say so |
| Arrival gaps every second, max gap far above 8.33 ms, decode time normal, shown for nearly all 8.3 ms or 25+ ms | Frames reach the iPad in clumps with holes between them, so the picture freezes for the length of each hole. No presenter can fix that. The 25 Oct pacing run saw this (90 gaps in 45 s, up to 141 ms). Check the iPad's Wi-Fi: the band, and AirDrop, Handoff and Cursor and Keyboard, which share the radio (AWDL). Ask the owner to turn those off, then run D again |
| Display: "late" above 1% | Frames are drawn too late for their refresh: the GPU or the compositor is slow. Compare the GPU time in an Instruments trace |
| "skipped" above 0 | The compositor threw drawables away: frames lost without being counted as drops |

### The A/B runs

Open https://www.testufo.com on the PC's streamed screen first (ask the owner). Keep the app's
settings as in phase 1a: Safe Area (2420x1668), 120 FPS, HEVC, 70 Mbps, Frames to buffer 2,
Statistics Overlay on. Run `testStreamAndSample` once per row with only the listed variables, and
`TEST_RUNNER_STARWIRE_SECONDS=120` unless the row says otherwise. Tell the owner before L that it
is the old render loop and will stutter: it is the baseline, not the fix.

| Run | Variables | Why |
| --- | --- | --- |
| L | none | The render loop with the new counters: shows how frames are lost |
| D | `TEST_RUNNER_STARWIRE_PRESENTER=display` | The display-driven presenter |
| D5 | `TEST_RUNNER_STARWIRE_PRESENTER=display`, `TEST_RUNNER_STARWIRE_SECONDS=300` | Only if D is under 1%: five minutes to confirm |
| V | `TEST_RUNNER_STARWIRE_PRESENTER=display`, `TEST_RUNNER_STARWIRE_VIRTUAL_DISPLAY=1` | Vibeshine streams a 120 Hz virtual display instead of the 480 Hz monitor |

V changes what the PC shows: ask the owner first. Before V, quit Desktop on the PC (tap the tile
on the iPad, then Quit App), or the test taps Resume App and the session stays on its old
display. Then ask the owner whether the PC really switched (testufo.com shows the refresh rate),
and open testufo.com on the virtual display.

The app sends `virtualDisplay=1` on both launch and resume (a unit test checks the request).
Vibeshine's source honours it on its own, even with the host's virtual display mode off, so if the
PC still streams the monitor, the reason is on the PC. Ask the owner to look in Vibeshine's log
(web UI > Troubleshooting) right after the launch for `Virtual display created`, `Virtual display
creation failed`, `SudaVDA driver unavailable`, `Rejecting per-client virtual display`, or
`Joining the running game's active capture output` (that one means it resumed a running session),
and for the Vibeshine version. Put what was found in the report.

For each run, put in the report: the summary line, the drop percentage at about 60 s and at the
end, the "Shown for" line at the end, decode to screen, network latency and decode time. Then
say which presenter was better, and whether the display presenter's decode to screen latency was
higher than the loop's. If D is under 1% with no added latency, the owner can make it the default
in a later change.

### A deeper trace (optional)

Only if the numbers above don't explain the drops. An Instruments trace shows every frame's
display time, the GPU work and the app's `pacing` signposts on one timeline. Start a stream (for
example `testStreamAndSample` with `TEST_RUNNER_STARWIRE_SECONDS=120`) and, while it runs, from
another terminal:

```bash
xcrun xctrace record --template "Metal System Trace" --device "$IPAD_UDID" --attach Starwire --time-limit 20s --output ../build/pacing.trace
open ../build/pacing.trace
```

In Instruments, the Display track shows how long each frame stayed on screen; the `pacing`
signposts (os_signpost) show decode, enqueue, drop and present. If `xctrace` asks for the Mac's
admin password, ask the owner; skip the trace rather than work around it. Traces don't go into
git: describe what they show in the report.

### Stability, serverinfo and logs

1. `testStreamsInARow` (10 streams) and `testBackgroundAndResume`. Report pass or fail, any alert
   text, and any crash (Xcode's Organizer, or the log's `stream` category).
2. serverinfo: with the app open on its PC list, the PC must show as online. From the Mac, also
   check both ports the app uses, with the PC's LAN address:

   ```bash
   curl -s -m 5 -o /dev/null -w "http %{http_code} %{time_total}s\n" "http://<PC LAN address>:47989/serverinfo"
   curl -sk -m 5 -o /dev/null -w "https %{http_code} %{time_total}s\n" "https://<PC LAN address>:47984/serverinfo"
   ```

   The first run's app log showed every HTTP request to 47989 timing out while pairing and
   streaming worked. This branch polls a paired PC over HTTPS (47984) with its pinned
   certificate, so the app no longer depends on 47989. If curl shows HTTP timing out too, the PC
   side is worth a look (Vibeshine serves HTTP serverinfo on one shared worker thread, which an
   encoder probe can hold up); note it in the report, but it's not this branch's to fix.
   curl has no client certificate, so HTTPS gets no answer: Vibeshine closes the connection in
   the TLS handshake (curl exit 56, code 000, in about 0.1 s). That is normal; a timeout is not.
3. Logs: start the app with `devicectl ... --console` (section 5) on a Release build and confirm
   lines from the app itself appear, for example `[network] <INFO> Starting mDNS discovery` at
   launch. The pacing settings line only comes when a stream starts, so it needs a stream while
   the console is attached. Quote one line in the report.

## 8. Write the report

Copy the template and fill in every field. Write "not checked" rather than leaving one out.

```bash
cd ..
cp docs/ios/device-runs/TEMPLATE.md "docs/ios/device-runs/$(date -u +%Y-%m-%d)-$(git branch --show-current | tr / -).md"
```

Put screenshots next to it as `docs/ios/device-runs/<same name>-1.png` and so on. The repo is
public: look at every picture first, and crop or leave out any that show the PC's browser tabs,
files, or the Apple ID (iPad Settings shows its email). Logs don't go into git: quote the lines
that matter in the report.

Commit only the report and its pictures, in UTC, following the rules in `AGENTS.md`:

```bash
git add docs/ios/device-runs/
TZ=UTC git commit -m "docs(ios): add the device run for $(git branch --show-current)"
bash .github/tools/check-commits.sh
git push
```

If the run showed this runbook was wrong, fix it in the same push.
