# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Starwire adopted
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) in 0.2.1, so every release after it is
numbered by SemVer's rules; 0.2.1 keeps the number it was announced with.
[RELEASING.md](docs/dev/RELEASING.md#version-numbers) explains what that means for an app, and the
few places Starwire can't follow it exactly.

The release pages on [GitHub](https://github.com/SicarioGaming/Starwire/releases) have the install
steps and the checksums for each version.

## [Unreleased]

### Added

- **The start of Starwire for iPad and iPhone,** under `ios/`: official moonlight-ios with its
  history, Andy Grundman's Metal renderer and Nonary's moonlight-common-c, built for the iOS
  simulator by GitHub Actions. It hasn't run on an iPad yet. The plan is
  [docs/ios/port-plan.md](docs/ios/port-plan.md), and the Mac steps are
  [docs/ios/mac-runbook.md](docs/ios/mac-runbook.md).
- **iOS: an app log in Release builds.** Logs go to the system log with a category per area
  (stream, video, pacing, network, input, audio), with signposts around decode, enqueue, drop and
  present. Extra detail is behind "Verbose logging" in Starwire's page in iOS Settings.
- **iOS: frame pacing measurements.** Every 5 seconds the log, and the statistics overlay, say
  how frames arrived and why they were dropped. iOS Settings has test choices for present timing,
  drop policy and frames to buffer, and a "Use a virtual display" switch for Vibeshine.
- **iOS: on-screen timing in the statistics overlay.** How long each frame stayed on screen, in
  steps of 4.2 ms (8.3, 12.5, 16.7 ms and so on), the display's refresh interval, the time from
  decoding to the screen, and a summary line for the whole stream. The summary line also counts
  gaps of more than 2.5 frames between arriving frames, and the longest time a frame stayed up.
- **iOS: a display-driven presenter, now the default.** A CAMetalDisplayLink draws a frame at
  each display refresh, as Nonary's moonlight-qt does on macOS. On the iPad Pro M4 it was as smooth
  as the old render loop with about 12 ms less from decoding to the screen. "Presenter" in iOS
  Settings still offers the old loop.
- **iOS: network arrival in the statistics overlay.** A "Network:" line says how often frames
  reach the iPad late (gaps of more than 2.5 frames, measured from their packets before any
  decoding), the longest gap, how regular the gaps are, how many frames come bunched together,
  and whether the host itself skipped frames. The summary line adds the time from a frame's last
  packet to the screen.
- **iOS: a jitter buffer for the display-driven presenter,** with Starwire for Android's four
  choices in iOS Settings: lowest latency (always the newest frame), low latency (up to 1 frame
  held back, the default), balanced (up to 2) and smooth (up to 4). It holds back only as many
  frames as the recent gaps need, repeats the last frame when it runs dry, and catches up one frame
  at a time. On patchy Wi-Fi, smooth rode out the most gaps in the tests, for about 23 ms more.
- **iOS: Full and Lite statistics overlays, with 1% low.** "Statistics overlay" in iOS Settings
  picks every line (Full) or one line (Lite): frame rate, 1% low, drops, latency, decode time and
  the display's measured refresh rate. 1% low is the frame rate of the slowest 1% of on-screen
  frame times over the last 5 seconds.
- **iOS: an even 60 FPS on a 120 Hz screen with the display-driven presenter.** Each frame now
  stays up for two refreshes; before, frames that landed near a refresh alternated between 8.3
  and 25 ms on screen.
- **iOS: "Allow refresh rate reduction",** off by default as on Android: the display stays at its
  top rate, so a 60 FPS stream can show each new frame at the next 120 Hz refresh. On, the display
  drops to the stream's rate to save power.
- **iOS: 4:4:4 at 8 bits and full range video.** A 4:4:4 stream now decodes at its own bit depth
  (it was always 10 bit), and "Force full range video" in iOS Settings asks the PC for full range,
  as on Android. The renderer takes the range from the decoded pixels, so the colours match
  either way. Vibeshine on an NVIDIA card encodes 4:4:4 with HEVC only, not AV1.
- **iOS: HDR10 with EDR.** HDR streams are decoded to linear light and shown with the stream's
  HDR10 metadata, so iPadOS maps them to the panel's brightness, as VoidLink does. The layer goes
  back to SDR when the PC leaves HDR. Not yet checked by eye on the iPad.
- **iOS: picture in picture,** off by default as on Android. With "Picture in picture" on in iOS
  Settings, leaving the app keeps the stream going in a small window you can watch but not
  control. Coming back closes the window; closing it while away ends the stream.
- **iOS: video on an external display.** "External display" in iOS Settings can put the stream's
  video on a plugged-in or AirPlay display while the touch controls stay on the iPad or iPhone.
  Mirroring stays the default. Not yet tried with a display.
- **iOS: frame interpolation on iPadOS and iOS 26 or later,** off by default. VideoToolbox makes
  a frame between each pair, so a 60 FPS stream shows at 120 Hz, for about half a frame of extra
  latency plus the processing time. It runs only at sizes the device allows: on the iPad Pro M4,
  1080p at 60 FPS worked, with about 14.5 ms per made-up frame, and 2420x1668 is too large.
- **iOS: unit tests on the simulator in CI,** including Andy Grundman's frame queue tests, and a
  UI test the Mac runs on the iPad.

### Changed

- **iOS: moonlight-common-c now comes from the owner's fork** (`starwire-ios`), which is Nonary's
  pinned commit plus five official fixes, including the RFI and partial IDR frame loss fixes.

### Fixed

- **iOS: the overlay's audio bitrate and decode time.** Reading the overlay twice within a few
  milliseconds showed bitrates in the billions of kbps, and the decode time showed "nan" or 0.00.

- **Prebuilt file check:** `verify.sh` now finds files listed in `SHA256SUMS` whose path has a
  space.
- **iOS: stream stability fixes, not yet tried on the iPad.**
  - Each frame is held on screen for the nearest whole number of refreshes. Holding it for a full
    1/120 s could make it miss a refresh at 120 FPS.
  - The renderer no longer waits for the GPU after every frame, and no longer polls for frames.
  - It could deadlock on the main thread when a stream stopped during a color change.
  - It could crash on a frame with no color information or an unknown pixel format.
  - A stream stopping late could stop or draw into the next one, and a stream closed while it
    was launching still connected (fixes from daniel-zn's Artemis iOS).
  - Two error alerts could open at once.
  - The app uses the UIScene lifecycle that iOS will require.
  - A paired PC is checked over HTTPS, so a PC whose plain HTTP port doesn't answer isn't shown
    as offline.
- **iOS: app tiles and PC cards have accessibility labels.** VoiceOver read nothing for a tile
  showing box art.
- **iOS: a normal launch no longer logs "Loading frame already shown!" as an error.** It is
  expected when one PC is saved.

## [0.2.1] - 2026-10-23

The repo changes that followed u/rambo3349's code review went live on GitHub before this release.

### Added

- **Custom resolutions and frame rates,** in the main settings and per game. These come from
  Moonlight X, credited to them.
- **A jitter buffer per game,** also from Moonlight X. It's used with host frame timing pacing.
- **The floating menu button stays where you put it:** Starwire remembers its spot for each
  orientation.
- **An about page** with credits and the full open-source licences.
- **Prebuilt libraries:** every one is traced back to its source and rebuilt byte for byte by
  GitHub ([PROVENANCE.md](docs/PROVENANCE.md)).
- **Mic measurements:** the 0.2.0 numbers are published with the raw data and a script that
  recomputes them ([here](docs/measurements/2026-10-22-mic/)), with two rounded numbers corrected.
- **Security and contributing:** a [SECURITY.md](SECURITY.md) with private vulnerability
  reporting, and a [CONTRIBUTING.md](CONTRIBUTING.md).
- **Checksums** are on the release pages, so you can check your download.
- **Tests:** 314 unit tests (from none), 32 of them screenshot tests, and 138 on-device tests. The
  same tests also run on 5 virtual devices, including a Fold shape folded, half-open and unfolded
  (thank you to u/MickeyBronson). Checks run automatically on every change.
- **This changelog,** and rules for commit messages
  ([Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)) and branch names
  ([Conventional Branch](https://conventionalbranch.org)), checked on every pull request.
  CONTRIBUTING.md explains them. Thank you to u/stiky21 for suggesting these.

### Changed

- **Less mic delay:** the PC side plays through a faster Windows audio path. In my tests the
  median delay dropped from about 114 to 98 ms, with far fewer dropouts.
- **The mic setup window** fits small screens, like a 1280x720 stream.
- **The custom driver option** is marked experimental, with a plain warning before you turn it on.
  Starwire now checks each driver file before it loads it, so a driver imported in 0.2.0 has to
  be chosen again.
- **Clearer about what's experimental:** the custom Turnip driver is now described as an
  experimental option, not listed with the speed features.
- **Send my microphone to** has a third choice, **Not encrypted**, for Voicemeeter and other VBAN
  apps. If you used 0.2.0's default, Starwire switches you to the encrypted receiver once.
- The app says Starwire, not Moonlight, where it talks about itself, like the network test and the
  decoder crash message. In Czech, Hungarian, Turkish and Tamil those few lines show in English
  for now.
- **Real commit history:** every commit now has its own description, and the repo shares history
  with Moonlight X again, so upstream updates can be merged properly.
- Various other small cleanups to the GitHub repo and changes to wording for transparency.
- **Version numbers** follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) from now
  on, also at u/stiky21's suggestion: fixes raise the last number, new features or anything that
  needs care when you update raise the middle one. Earlier releases keep their numbers and links.
  [RELEASING.md](docs/dev/RELEASING.md#version-numbers) has the details, including why this
  release is still 0.2.1.

### Removed

- The Unlock FPS setting. The Custom frame rate takes its place.
- The 360p and 480p presets (you can still enter them as custom resolutions), and the native
  resolution and frame rate warnings.

### Fixed

- The PC's cursor comes back if Starwire is closed or crashes while it's hidden, and there's a
  "Fix PC cursor" button in the stream menu.
- No more "PC not paired" flicker on the games screen.
- No more crash on RedMagic devices when the games screen resizes.
- No more crashes from some unusual host replies, or on the resume button on Android 5 and 6.
- A rare video mix-up with async decoding after a hiccup is fixed.
- On Android 5 to 7, the background animations now stop when animations are turned off (saves
  battery).
- The in-stream menu and the games screen fit small screens better.
- Each section button at the top of Settings scrolls all the way to its heading. On-screen
  controls, and now and then About, used to stop short.
- TalkBack can read the game covers and PC cards, and the Play, Resume and Quit buttons say which
  game they're for.

### Security

- **Encrypted microphone:** the mic is now encrypted, and only devices you've paired can send
  audio to your PC. Being on the same network is no longer enough, and encryption no longer
  requires Tailscale or a similar VPN.
- **Updating from 0.2.0** needs both sides: update the app, run the new setup on the PC, then pair
  once. Until both are updated the mic doesn't work, because the new receiver refuses 0.2.0's
  unencrypted audio and a 0.2.0 receiver doesn't understand the new app.

Known issues: right-to-left languages (Hebrew, Persian) show translated text, but the layout
doesn't mirror yet. On very narrow screens, the Quit and Disconnect buttons can cut their labels
short. The custom Turnip driver option still hasn't been tried with a real Turnip driver.

## [0.2.0] - 2026-10-23

Your microphone on the PC, with any host. Talk in Discord or in-game voice chat through your
Android device while you stream, with Vibepollo, Sunshine or Apollo as they are.

### Added

- **Microphone:** Starwire sends your voice to a small receiver on the PC, which plays it into
  VB-Cable, a free virtual microphone. Discord or the game picks it up as a normal mic, and your
  host doesn't change. Turn it on in **Settings → Sound & vibration → Send my microphone**.
- Starwire turns on the device's echo cancelling and noise reduction where it has them.
- **Starwire-Microphone-for-Windows.zip** with `setup-microphone.cmd`, a one-time setup for
  Windows 10 or 11. It builds the receiver from its source with the C# compiler that comes with
  Windows, installs VB-Cable if needed (after checking VB-Audio signed it), lets the receiver
  through Windows Firewall for local-network and private VPN addresses only, starts it at every
  sign-in and plays a test tone. `-Uninstall` removes it again.
- The receiver's icon by the clock: right-click it to check the virtual mic, play a test tone
  (for Discord's mic test) or quit.
- With [logabell's Apollo build](https://github.com/logabell/apollo-microphone/releases), set
  **Send my microphone to** to **The PC's streaming app** and the microphone goes over the stream
  itself. Thanks to logabell for that code.
- A Quit button beside Resume while a game is running, so you don't have to long-press the tile.
- Games without cover art each get their own take on the Starwire tile (colour, ring, moon, glow)
  instead of all looking the same.
- Settings that change latency, smoothness, picture quality or battery have a short **Impact:**
  line under them, so you can see what turning one on or up gains or costs.
- Stream menu items that switch something on or off (Stats, Mouse mode, Keyboard, Pan and zoom,
  Touch sensitivity, On-screen controller, Menu button) show a small switch, and tapping them
  keeps the menu open.
- The stream menu header shows the game's cover art. Desktop and games without cover art get a
  Starwire tile.

### Changed

- The top of the game screen scrolls away with your games. On a small screen held sideways it used
  to fill most of the screen. Once it's gone, a slim bar keeps the selected game and its Play
  button at the top; tap the bar to scroll back up.
- The game screen fits small screens: a smaller cover and title, and the Play and settings buttons
  stack.
- On a small screen held sideways, the stream menu puts Close, Quit and Disconnect on one row, so
  more tools fit.
- On a foldable's inner screen, the stream follows how you hold it instead of forcing landscape,
  which could leave it small with black borders.
- The floating menu button is smaller, see-through until you touch it, and closes the menu as well
  as opening it.
- Softer corners, covers that arrive one after another and give a little when you press them, and
  a gently floating cover. The screen's animations pause while you stream.
- The Lite stats line uses plain words: data rate, ping, decode time, dropped frames and FPS.

### Fixed

- Settings now show on narrow screens. On a small device held upright or a Galaxy Z Fold's cover
  screen they were blank.
- Tapping a running Desktop tile to reconnect no longer crashes the app (the Resume button already
  worked), and neither does long-pressing Desktop or another icon tile. Create shortcut now works
  for them too.

Known issues: the microphone audio isn't encrypted or authenticated. Anyone else on the same
network could listen to it, or send their own sound into the PC's virtual mic, so use it only on a
network you trust, or over Tailscale. 0.2.1 encrypts it.

## [0.1.2] - 2026-10-22

### Fixed

- The crash when opening a PC's games. In 0.1.0, Starwire closed a moment after the list of games
  appeared, right as the first cover art arrived. Cover art now loads without crashing, and the
  screen picks up each cover's colour as intended.

## [0.1.0] - 2026-10-22

The first release of Starwire. If you installed it under its earlier name, Voidlink, this is the
same app renamed; it installs separately, so you can uninstall Voidlink afterwards.

### Added

- The best features of the Android Moonlight clients in one app: Moonlight X's video pipeline, the
  touchscreen tools from Artemide and Artemis, and favourites from Moonlight V+, Moonlit Artemis
  and Moonlight X Turnip. It installs next to any Moonlight you already have.
- **A new look:** the screens take their colour from the game you pick, over a starfield. Apps
  without cover art, like Desktop and Steam Big Picture, get their own icons.
- **Touchscreen tools:** the floating menu button, the Shortcuts page, pan/zoom, touch modes, the
  full keyboard, clipboard sharing, PC commands and Virtual Display.
- **Video options:** Warp Drive, Fast V-Sync, LFR and async decoding. I haven't measured how much
  they change latency in Starwire. There's also an experimental setting to load your own Turnip
  driver for PyroWave. It's off by default and hasn't been tried with a real Turnip driver yet.
- **Extras:** monitor switching, pinch to zoom anytime, changing the bitrate mid-stream, audio
  haptics and shortcuts imported from a file.

[Unreleased]: https://github.com/SicarioGaming/Starwire/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/SicarioGaming/Starwire/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/SicarioGaming/Starwire/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/SicarioGaming/Starwire/compare/v0.1.0...v0.1.2
[0.1.0]: https://github.com/SicarioGaming/Starwire/releases/tag/v0.1.0
