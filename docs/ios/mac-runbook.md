# Mac runbook: build, sign and test Starwire on the iPad

Steps for Claude Code (or a person) on the owner's M1 Mac. The Windows PC writes the code and
GitHub Actions builds it for the simulator; this Mac is the only place the app is signed,
installed on the iPad and tested against the PC. The plan is [port-plan.md](port-plan.md).

Written 25 Oct 2026, before any of it was run on the Mac. Fixed after the first run
([device-runs/2026-10-24-feature-ios-phase-0.md](device-runs/2026-10-24-feature-ios-phase-0.md)).
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

Then the iOS submodules only (Android's aren't needed on the Mac):

```bash
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
log. Even with it, a Release build shows only system lines: `Logger.h` compiles the app's own
`Log()` calls out unless `DEBUG` is set. Build Debug when you need the app's log. The log stops
when the app is closed on the iPad; a copy started from the home screen isn't logged.

## 6. Run the tests

StarwireKit, the Swift package with no UIKit:

```bash
swift test --package-path StarwireKit 2>&1 | tee ../build/starwirekit-tests.log
```

The same simulator build as CI, to tell a Mac-only problem from a code problem:

```bash
xcodebuild -project Starwire.xcodeproj -scheme Starwire -configuration Debug -destination "generic/platform=iOS Simulator" -derivedDataPath ../build/DerivedData CODE_SIGNING_ALLOWED=NO build 2>&1 | tee ../build/simulator-build.log
```

The app target has no XCTest or UI tests yet. Phase 1 adds them; this section then gets their
command.

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

These checks can be run without anyone at the iPad by a UI test (XCUITest). The first run used a
local one, not in git: a spec `ios/devicerun.yml` that includes `project.yml` and adds a
`bundle.ui-testing` target, generated with `xcodegen generate --spec devicerun.yml` and run with
`xcodebuild test -configuration Release -destination "id=$IPAD"`. The overlay is a plain label, so
the test reads its text. `xcodebuild test` installs over the app and keeps the pairing. On the
iPad Pro, `XCUIDevice.shared.press(.home)` did not send the app to the background; activating the
Settings app (`com.apple.Preferences`) did. The UI test's runner is a second signed app, which
counts toward a free account's 3 apps.

The renderer in this build is Andy Grundman's Metal one (it replaced upstream's
`AVSampleBufferDisplayLayer` renderer), so a working stream is a working Metal path.

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
TZ=UTC git commit -m "docs(ios): add the device run for feature/ios-phase-0"
bash .github/tools/check-commits.sh
git push
```

If the run showed this runbook was wrong, fix it in the same push.
