# Mac runbook: build, sign and test Starwire on the iPad

Steps for Claude Code (or a person) on the owner's M1 Mac. The Windows PC writes the code and
GitHub Actions builds it for the simulator; this Mac is the only place the app is signed,
installed on the iPad and tested against the PC. The plan is [port-plan.md](port-plan.md).

Written 25 Oct 2026, before any of it was run on the Mac. Fixed after the first run
([device-runs/2026-10-24-feature-ios-phase-0.md](device-runs/2026-10-24-feature-ios-phase-0.md))
and the phase 1a run
([device-runs/2026-10-25-feature-ios-phase-1a.md](device-runs/2026-10-25-feature-ios-phase-1a.md)).
When a run shows something else wrong here, fix this page in the same branch as that run's report.

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
| `testStreamAndSample` | Starts the app tile, reads the statistics overlay every 15 seconds for `STARWIRE_SECONDS` (default 300), takes screenshots at the start and end, stops with an edge swipe, and checks the app list is back with no alert |
| `testBackgroundAndResume` | Starts a stream, switches to the Settings app for 10 seconds, comes back, checks the app list is showing with no alert, then streams and stops once more |
| `testStreamsInARow` | Starts and stops `STARWIRE_STREAMS` streams (default 10), 10 seconds each, checking for an alert and that the app is still running after each |

Options are environment variables with a `TEST_RUNNER_` prefix, which `xcodebuild` passes to the
test. The test turns them into the app's launch arguments; the app has no code for tests.

| Variable | Values |
| --- | --- |
| `TEST_RUNNER_STARWIRE_APP` | app tile to start, default `Desktop` |
| `TEST_RUNNER_STARWIRE_SECONDS` | stream length for `testStreamAndSample` |
| `TEST_RUNNER_STARWIRE_STREAMS` | streams for `testStreamsInARow` |
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

## 7a. Phase 1a checks (`feature/ios-phase-1a`)

Phase 1a is done when, on the iPad:
- pacing drops are under 1% at 120 FPS with moving content, or the report explains with
  measurements why not and names the best setting found;
- 10 streams in a row, plus background and resume, end with no crash and no double alert;
- the PC shows as online (serverinfo works over the network);
- the app's own log lines are readable from a Release build.

### What the first run showed, and what this branch changes

At 2420x1668, 120 FPS, HEVC, 70 Mbps with testufo.com moving on the PC, the overlay showed 0%
network drops but 12.1% to 13.5% pacing drops, steady for 5 minutes, with a frame queue of 1.5 to
1.9 and "Frames to buffer" at 2. About 120 FPS arrived and about 105 FPS were shown.

A drop that steady, with no network loss, looks like the screen taking frames more slowly than
they arrive, not like bursty arrival: with a queue of 2 and a consumer that can only take one
frame per refresh, any refresh where the previous frame stays up twice leaves one frame too
many, and the queue drops it. The code has a likely cause. Every frame was presented with
`presentDrawable:afterMinimumDuration:1/fps`. At 120 FPS on a 120 Hz screen that is exactly one
refresh, so a frame that comes up a few microseconds short of a full refresh has to wait for the
next one and stays up for two. About 15 such refreshes a second would explain 120 in and 105
out.

This branch:
- holds each frame for the frame interval minus half a refresh ("nearest" present timing), so
  at 120 on 120 Hz a frame stays up for one refresh, and at 60 on 120 Hz for two;
- counts, for every 5 second window, how frames arrived (bursts under half a frame apart, on
  time, late) and how many refreshes each frame stayed up, and gives every drop a reason
  (incoming frame dropped, or oldest dropped to make room) and says whether it came right after a
  burst. The log has the full line (`pacing window ...` in the `pacing` category); the overlay's
  last line is the short version:
  `Pacing: bursts x%, drops after burst n, held 2+ refreshes y%, skipped n`;
- keeps the old behaviour one setting away, for the A/B runs below.

How to read a window:

| What the numbers show | What it means |
| --- | --- |
| "held 2+ refreshes" about equal to the drop rate, few bursts | The screen is the bottleneck (the present-timing theory) |
| Many bursts and most drops "after burst", "held 2+" near 0 | Frames arrive in clumps (host capture timing or Wi-Fi); a deeper buffer or a virtual display may help |
| "skipped" above 0 | The compositor threw drawables away: frames lost without being counted as drops |
| Drops near 0 but "held 2+" high | Frames arrived late (starved), not dropped: look at network latency |
| Drops steady, bursts 0, "held 2+" far below the drop rate | The consumer takes frames off the queue more slowly than they arrive, but not one refresh at a time: look at the render loop, not pacing policy (the phase 1a run) |

### The A/B runs

Open https://www.testufo.com on the PC's streamed screen first (ask the owner), or any video at
120 FPS. Keep the app's settings as in the first run: Safe Area (2420x1668), 120 FPS, HEVC,
70 Mbps, Frames to buffer 2, Statistics Overlay on. Run `testStreamAndSample` once per row, 300
seconds each, with only the listed variables set. If the drop rate is steady from sample to
sample, 120 seconds (`TEST_RUNNER_STARWIRE_SECONDS=120`) is enough; say so in the report.

| Run | Variables | Why |
| --- | --- | --- |
| A | `TEST_RUNNER_STARWIRE_PRESENT_TIMING=frame` | The old rule: should reproduce about 12% |
| B | none (nearest, alternate, buffer from the app) | The fix |
| C | `TEST_RUNNER_STARWIRE_DROP_POLICY=newest` | Keep the newest frame instead of alternating |
| D | `TEST_RUNNER_STARWIRE_BUFFER=3` | A deeper queue; adds about 8 ms of latency, so only worth it if it removes drops B can't |
| E | `TEST_RUNNER_STARWIRE_VIRTUAL_DISPLAY=1` | Vibeshine captures a 120 Hz virtual display instead of the 480 Hz monitor, which may even out arrival |

Run A and B always. Run C, D and E if B is still at 1% or more, or if B's windows show bursts.
E changes what the PC shows: tell the owner first, and open testufo.com on the virtual display.
Before E, quit Desktop on the PC (tap the tile on the iPad, then Quit App): if it is still
running, the test taps Resume App and the session stays on the display it started on. Then ask
the owner whether the PC really switched (testufo.com on the PC shows the refresh rate). In the
phase 1a run Vibeshine kept streaming the 480 Hz monitor even on a fresh launch.

For each run, put in the report: the drop percentage from the overlay at about 60 s and at the
end, the mean over all samples, the pacing line, the network latency, and the decode time. If
the log could be collected, add two `pacing window` lines (PC addresses removed). Then say which
setting was best. The goal is under 1% pacing drops without a deeper buffer than 2.

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
