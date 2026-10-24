# Mac runbook: build, sign and test Starwire on the iPad

Steps for Claude Code (or a person) on the owner's M1 Mac. The Windows PC writes the code and
GitHub Actions builds it for the simulator; this Mac is the only place the app is signed,
installed on the iPad and tested against the PC. The plan is [port-plan.md](port-plan.md).

Written 25 Oct 2026, before any of it was run on the Mac. The first run will show what is wrong
here: fix this page in the same branch as that run's report.

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
| macOS | 15.6 or later | `sw_vers` |
| Xcode, with the iOS platform | 26 or later | `xcodebuild -version` and `xcodebuild -showsdks` (lists `iphoneos`) |
| Homebrew | any | `brew --version` |
| XcodeGen | any recent | `xcodegen --version` |
| git | any | `git --version` |
| Claude Code | any | |

```bash
brew install xcodegen
xcodebuild -downloadPlatform iOS   # only if xcodebuild -showsdks lists no iphoneos
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

   Use the `teamID` of the entry with `isFreeProvisioningTeam = 1`. If that key doesn't exist,
   try `defaults read com.apple.dt.Xcode IDEProvisioningTeams`, or select the team in a project's
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
Management > the Apple ID > Trust.

Start it from the Mac, with its log in the terminal and in a file:

```bash
xcrun devicectl device process launch --console --device "$IPAD" io.github.shev0k.starwire 2>&1 | tee ../build/device-run.log
```

If `--console` isn't there in this Xcode, start the app on the iPad and read its log in
Console.app (select the iPad, filter by "Starwire").

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
2. In Settings: Resolution to the iPad's native resolution (or the closest one offered), Frame
   Rate 120 FPS, Preferred Codec HEVC, Statistics Overlay on. Write down the bitrate it shows.
3. Start Desktop. Stream for at least 5 minutes, moving windows and playing a video on the PC so
   frames keep changing.
4. Take screenshots of the statistics overlay at the start and near the end (top button + volume
   up). Note frame rate, dropped frames, decode time and network latency from it.
5. Background the app, come back, and stop the stream. Note any crash or hang.

The renderer in this build is Andy Grundman's Metal one (it replaced upstream's
`AVSampleBufferDisplayLayer` renderer), so a working stream is a working Metal path.

## 8. Write the report

Copy the template and fill in every field. Write "not checked" rather than leaving one out.

```bash
cd ..
cp docs/ios/device-runs/TEMPLATE.md "docs/ios/device-runs/$(date -u +%Y-%m-%d)-$(git branch --show-current | tr / -).md"
```

Put screenshots next to it as `docs/ios/device-runs/<same name>-1.png` and so on. Logs don't go
into git: quote the lines that matter in the report.

Commit only the report and its pictures, in UTC, following the rules in `AGENTS.md`:

```bash
git add docs/ios/device-runs/
TZ=UTC git commit -m "docs(ios): add the device run for feature/ios-phase-0"
bash .github/tools/check-commits.sh
git push
```

If the run showed this runbook was wrong, fix it in the same push.
