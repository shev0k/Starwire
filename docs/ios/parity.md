# iOS parity table

This table tracks which Starwire for Android features and settings the planned iOS client will
have. It comes from [port-plan.md](port-plan.md), the Android README and the two Android
preference files, as of 25 Oct 2026 (phase 0), with statuses updated by each device run (last:
[batch 3](device-runs/2026-10-25-feature-ios-batch-3.md)). Rows marked "check" are open questions for the phase that builds them.

Status values:

- **planned**: the plan builds it. Not started.
- **built**: in the code with unit tests, CI green, not yet shown working on the iPad.
- **verified**: a device report shows it working on the iPad.
- **not possible**: iOS can't do it (the "Not possible on iOS" table in the plan).
- **host lacks it**: Vibeshine doesn't have it, so the app doesn't build or show it.

When a feature is built, the status moves to `built` (CI green), then `verified` (a device report
links to it). Only `verified` counts as done. The Phase column is the phase in the plan, or `-`
when there is no phase because the feature can't exist or the host lacks it.

## Features

| Feature | Phase | Status | Notes |
|---|---|---|---|
| Pairing with a PIN | 1 | built | Client key and certificate in the Keychain, moved unchanged from the old files: the iPad stayed paired through the move, the files' removal and a reinstall ([batch 2](device-runs/2026-10-25-feature-ios-batch-2.md)). Pinned-certificate refusal grace (30 s), asking a paired PC again before showing it unpaired, MAC preservation and mDNS polls over HTTPS are unit tested. The PIN flow itself wasn't run again |
| Host list with frosted cards | 3 | planned | SwiftUI |
| Game screen hero, with cover colours and a background that follows the game | 3 | planned | |
| Tiles for apps without cover art (generated Starwire tiles, icon tiles) | 3 | planned | |
| Starfield, rainbow wordmark and cover animations | 3 | planned | Honour Reduce Motion. Pause while streaming |
| Quick Launch | 3 | planned | |
| Per-game settings and the overrides bar (bitrate and stats overrides) | 3 | planned | The store is built (StarwireKit `GameSettings`, Android's JSON and merge rules). Screens in phase 3 |
| App menu: virtual or primary display, per-game settings, hide app, details | 3 | planned | |
| Settings screen with section pills, plain names and "Impact:" lines | 3 | planned | |
| Predicted impact panel | 3 | planned | Shown on iPad |
| Settings export and import as JSON | 1 | built | StarwireKit's `SettingsJSON`, with Android's keys and types and per-game settings. Android has no export yet, so this is the format both should use. No screen for it until phase 3 |
| About page, credits and open-source licences | 3 | planned | |
| 33 translations | 3 | planned | Converted from `strings.xml` by a script |
| In-app language picker | 3 | planned | Opens the app's language page in iOS Settings |
| Layouts for iPad (Split View, Stage Manager) and iPhone | 3 | planned | Replaces the foldable inner-screen handling. iPhone checked on the simulator only |
| VoiceOver, Dynamic Type and Reduce Motion | 3 | planned | New on iOS, not an Android feature |
| Controller navigation of every screen | 3 | planned | |
| Custom resolutions and frame rates | 3 | planned | |
| Auto-resume stream after sleep | 1 | planned | The stream stops in the background except in picture in picture. Check how resume should work |
| Stream menu as a side panel, opened by the floating button, a three-finger tap or holding a controller button | 5 | verified | A right-side sheet like Android's, from StarwireKit's StreamMenu. The floating button and the three-finger tap opened it on the iPad 10th gen: [batch 3](device-runs/2026-10-25-feature-ios-batch-3.md). Holding Select, Start, Guide or LB+RB is built and unit tested (Android's hold-back rules); hands-on with a controller pending |
| Floating menu button, with a saved spot per orientation | 5 | verified | Dragged and kept its landscape spot on the iPad 10th gen: [batch 3](device-runs/2026-10-25-feature-ios-batch-3.md). Portrait not tried |
| Stream menu on/off switches and the game's cover in the header | 5 | built | The Stats, On-screen Controls and Pan/Zoom switches worked on the iPad 10th gen ([batch 3](device-runs/2026-10-25-feature-ios-batch-3.md)). The header shows the game's name, the resolution and frame rate, and Android's tint as a swatch: no cover art yet (phase 3 brings the covers) |
| Keyboard and the on-screen full keyboard (82 keys, sticky modifiers, vibration) | 5 | verified | Android's layout has 80 keys (its XML has 82 with two commented out). Keys, a held Shift locking, and the system keyboard (text as UTF-8, Return as Enter) reached the PC on the iPad 10th gen: [batch 3](device-runs/2026-10-25-feature-ios-batch-3.md). Key vibration needs a vibration motor: iPhone only |
| Shortcuts page (14 built in, including Task Manager) | 5 | verified | Android's 14 plus Task Manager on the main page. Esc reached the PC from the page on the iPad 10th gen ([batch 3](device-runs/2026-10-25-feature-ios-batch-3.md)); every shortcut's packets are unit tested. Keys that change the PC (Win, Task Manager) weren't pressed in the device run |
| Custom shortcuts imported from a file | 5 | built | Starwire's JSON (`VK_` names or hex, 50 shortcuts of up to 8 keys), from the Files app through Manage on the menu's Shortcuts page. Parsing and limits unit tested; the picker not tried on the iPad |
| Custom commands in the stream menu, with close, disconnect or quit after | 5 | built | Android's format and timings, with an editor under Manage on the Shortcuts page (iOS has no settings screen of its own until phase 3). Unit tested; not tried on the iPad |
| Custom command that ends with "Sleep" | - | not possible | iOS apps can't lock or sleep the device |
| Monitor switcher (Monitor 1 to 6) | 5 | built | Sends Ctrl+Alt+Shift+F1 to F6, unit tested. Not pressed in the device run (it would switch what the PC streams). Whether Vibeshine switches displays on these keys is not checked |
| Touch modes: multi-touch, direct, natural trackpad, gaming trackpad, disabled, swapped clicks | 5 | verified | Ported from Android's touch contexts with their timings (StarwireKit, tested with injected time). All six on the iPad 10th gen: clicks, drags, the two-finger right click, long press, swapped clicks, touches passed through to Vibeshine and nothing sent when disabled: [batch 3](device-runs/2026-10-25-feature-ios-batch-3.md). Android's multi-touch passthrough never runs (its handler only fires for another view); iOS sends the touches |
| Trackpad sensitivity | 5 | built | 25 to 300% in iOS Settings, and the menu's Sensitivity switch, as on Android. The scaling is unit tested; the switch wasn't used in the device run |
| Pinch to zoom anytime, and Pan/Zoom mode | 5 | verified | A pinch and Pan/Zoom mode sent nothing to the PC, and a double tap reset the zoom, on the iPad 10th gen: [batch 3](device-runs/2026-10-25-feature-ios-batch-3.md). The zoom maths (one VideoGeometry for the picture and every input) is unit tested |
| Long-press to right-click | 5 | verified | Direct touch, on the iPad 10th gen: [batch 3](device-runs/2026-10-25-feature-ios-batch-3.md). The gaming trackpad's hold is unit tested |
| Hide PC cursor, with the "Fix PC cursor" button | 5 | built | Ctrl+Alt+Shift+N, with Android's crash-safe record per PC. Unit tested; not tried: whether Vibeshine has this toggle is not checked |
| On-screen controller with a layout editor | 5 | verified | Android's layout and stick maths. A and the left stick reached the PC, the editor moved a control and Reset put it back, on the iPad 10th gen: [batch 3](device-runs/2026-10-25-feature-ios-batch-3.md). Resizing and the opacity slider not tried on the device |
| Apple Pencil | 5 | built | Pressure through VoidLink's curves (Linear, Soft, Firm in iOS Settings), tilt and hover. Unit tested. Not tried: the iPad 10th gen used for batch 3 has no Pencil. Needs the iPad Pro |
| Hardware keyboard and mouse, with pointer lock | 5 | built | moonlight-ios's keyboard and GCMouse handling with pointer lock. Not tried: no keyboard or mouse in batch 3 |
| Back and forward mouse buttons, high-resolution scroll | 5 | built | Back and forward follow "Enable back and forward mouse buttons" (off by default, as on Android). Not tried on the device |
| Remote desktop mouse mode (absolute mouse) | 5 | built | The gaming trackpad sends moves as positions, unit tested |
| Root evdev mouse capture | - | not possible | No root access on iOS |
| Multiple controllers, deadzone, flip face buttons, analog scrolling | 5 | built | Android's rules (StarwireKit GamepadProcessor), unit tested. Hands-on with the DualSense, Apex 5 and grip pending |
| Mouse emulation and touchpad as mouse | 5 | built | Unit tested. Hands-on pending |
| Gamepad motion sensors, with the device gyro as fallback | 5 | built | Controllers' own sensors (moonlight-ios), and the device's through Core Motion with Android's axis table. Unit tested. Hands-on pending |
| Rumble, trigger rumble, adaptive triggers, LED and battery | 5 | built | Rumble, trigger rumble, LED and battery from moonlight-ios; adaptive triggers decoded as VoidLink does (unit tested). Hands-on pending |
| Emulated rumble with device vibration | 5 | built | Core Haptics on a device with a vibration motor. iPads have none, so iPhone only; not tried |
| DualSense waveform haptics (Vibeshine packet 0x5601) | 5 | built | The PCM becomes intensity, sharpness and transients every 10 ms (unit tested), played on the grips with Core Haptics. Close, not identical. Not tried: needs a game with DualSense haptics and Vibeshine's haptics component |
| Playing raw waveforms on the DualSense's actuators | - | not possible | No public iOS API |
| Xbox 360 / One USB gamepad driver | - | not possible | No raw USB access. Controllers iOS supports still work over Bluetooth or USB-C |
| System Home-button gesture disabled while streaming | 5 | built | moonlight-ios turns off the system gestures of every controller element. Hands-on pending |
| Metal renderer with host frame timing | 4 | planned | Replaces the Vulkan renderer. "Host-timed" is rebuilt on RTP timestamps |
| Pacing modes: Latency, Balanced, Cap FPS, Smoothness | 4 | planned | Rebuilt on the Metal presenter |
| Warp Drive and Warp 2 pacing | 4 | planned | Asks for 2x or 4x FPS and shows the newest frame |
| VRR pacing | 4 | planned | ProMotion with `clientVrrRequested` |
| Fast V-Sync and V-Sync options | 4 | planned | Where they apply on iOS |
| Sync: LFR, Async decode, Async: LFR | 4 | planned | Check: these are MediaCodec ideas. Decide what maps to VideoToolbox |
| Ultra low latency | - | not possible | Vendor decoder flags are Android only. VideoToolbox's real-time mode is used instead |
| Jitter buffer presets | 4 | verified | All four on the display presenter: [batch 1](device-runs/2026-10-25-feature-ios-batch-1.md). In iOS Settings for now; the app's settings come in phase 3 |
| HDR10, full range video | 4 | built | EDR on Metal. HDR10 (HEVC Main 10) and full range streamed at 120 FPS in [batch 1](device-runs/2026-10-25-feature-ios-batch-1.md); the picture not yet checked by eye |
| YUV 4:4:4 | 4 | verified | HEVC 4:4:4 at 120 FPS: [batch 1](device-runs/2026-10-25-feature-ios-batch-1.md). Vibeshine on NVIDIA has no AV1 4:4:4 |
| AV1, HEVC and H.264 codec choice | 4 | verified | AV1 and HEVC at 120 FPS on the M4: [batch 1](device-runs/2026-10-25-feature-ios-batch-1.md). H.264 not tried. AV1 only on devices with hardware AV1 |
| Spatial dithering | 4 | planned | |
| Stretch video, rotate, brightness slider | 4 | planned | |
| Reduce refresh rate, measured refresh rate | 4 | verified | 60 FPS at 120 Hz by default, 60 Hz with reduction: [batch 1](device-runs/2026-10-25-feature-ios-batch-1.md) |
| Full and Lite performance overlay, with 1% low FPS | 4 | verified | [batch 1](device-runs/2026-10-25-feature-ios-batch-1.md). Host CPU and GPU (phase 2) and ImGui graphs not yet |
| Post-stream latency message | 4 | planned | |
| Picture in picture | 4 | verified | AVSampleBufferDisplayLayer behind the Metal view. Starts on Home, closes on return: [batch 1](device-runs/2026-10-25-feature-ios-batch-1.md). How it looks not checked by eye |
| External display | 4 | built | Mirror, or the video on the display through a UIScene role. No display was there to try it. Not on Android |
| Frame interpolation | 4 | verified | iOS 26 or later. 1080p60 shown at 120 FPS: [batch 1](device-runs/2026-10-25-feature-ios-batch-1.md). The M4 allows up to 1920 on a side and about 2.07 million pixels, and each frame took about 14.5 ms. Not on Android |
| PyroWave codec | 7 | planned | Least certain. Needs a fast link. A 2-day trial on the iPad comes first |
| PyroWave late-frame presets | 7 | planned | |
| Custom Vulkan driver (Turnip, libadrenotools) | - | not possible | iOS apps can't load GPU drivers |
| Virtual Display: "Display on the PC" and Start in Virtual/Primary Display | 2 | verified | "Display on the PC" in iOS Settings: the PC decides, `virtualDisplay=1` or `virtualDisplay=0`. A virtual display at 2420x1668 and 120 Hz: [batch 2](device-runs/2026-10-25-feature-ios-batch-2.md). The PC's own monitor (`0`) not tried |
| Virtual display scale factor, VRR request and fractional refresh rates | 2 | verified | `scaleFactor` 150 made a 3630x2502 virtual display and `clientVrrRequested=1` a 1000 Hz one with the frame limiter at 120, both in the PC's log: [batch 2](device-runs/2026-10-25-feature-ios-batch-2.md). 119.88 Hz is sent in `mode`, but the PC's log only said "120 Hz", so the exact rate is not confirmed. `clientName` is sent; Vibeshine shows the name typed with the PIN |
| Change bitrate mid-stream | 2 | verified | `GET /bitrate` from the button in the stream's corner (phase 5 makes it the stream menu). 20 then 70 Mbps applied, no drops: [batch 2](device-runs/2026-10-25-feature-ios-batch-2.md) |
| Remote Monitor, Remote Input and Terminate tiles | 2 | built | Remote Input verified: [batch 2](device-runs/2026-10-25-feature-ios-batch-2.md). Remote Monitor: the PC failed to add its display (Windows refused the display change) and the app showed its message. Terminate appears only to a second client, so it needs another device. The HTTP 410 step is tested with Vibeshine's messages |
| Sleep the PC | 2 | built | `/power-actions/v1`, shown only when the PC allows this device. Vibeshine 2.0.1 doesn't have it (404), so not tried |
| Host CPU and GPU stats | 2 | built | `/api/hardware-metrics` in the overlay when the PC sends it. Vibeshine 2.0.1 doesn't have it (404), so not tried |
| Optimize game settings | 2 | planned | Check: standard launch option |
| Play audio on PC | 2 | planned | Check: standard launch option |
| Demo mode (no PC) | 1 | verified | iOS only: a made-up PC, a moving test picture and recorded touches, built on StarwireKit's fakes: [batch 2](device-runs/2026-10-25-feature-ios-batch-2.md) |
| Prevent packet loss (small keep-alive packet) | 4 | planned | Check: needs a call in Starwire's common-c fork. iOS uses Nonary's fork |
| Send/get clipboard and automatic clipboard sync | - | host lacks it | Vibeshine has no `/actions/clipboard`. The client checks serverinfo, so it can be turned on later |
| PC commands (server commands) | - | host lacks it | Vibeshine has no `ServerCommand` |
| Client FEC percentage request | - | host lacks it | FEC is set on the host (default 20%). Not a visible Android feature |
| MLCS clock sync for "host-timed" pacing | - | host lacks it | Rebuilt on RTP timestamps (see the Metal renderer row) |
| Apollo per-client permissions | - | host lacks it | Every paired client can launch and quit |
| Pen barrel roll | - | host lacks it | Vibeshine ignores packet 0x5500000B |
| Surround sound: stereo, 5.1 and 7.1, plus spatial audio | 6 | planned | AudioUnit output. No head tracking on a free account |
| Audio effects toggle (system equalizer) | - | not possible | iOS has no per-app system audio effects |
| Audio haptics from the game's bass, to a controller or the iPhone | 6 | planned | Strength 25 to 200%. Taptic Engine on iPhone |
| Audio haptics on the iPad itself | - | not possible | iPads have no vibration motor. iPhone and controllers still get it |
| Microphone to the PC through StarwireMicReceiver (SWMC, encrypted) | 6 | planned | `AVAudioEngine` with echo and noise cancelling. AES-256-GCM. Needs a security review and sign-off |
| Microphone pairing with the 16-character code | 6 | planned | Keys in the Keychain |
| Plain VBAN microphone ("Not encrypted") | 6 | planned | Fallback |
| Microphone device selection | 6 | planned | Where iOS offers several |
| Microphone over the stream (logabell's Apollo build) | - | host lacks it | `streamid=mic` gets a 404 on Vibeshine |
| Launcher shortcuts | 8 | planned | App Intents, the Shortcuts app and the `starwire://` URL scheme |
| Android TV channels and poster provider | - | not possible | No Android TV home screen on iOS |
| Wake-on-LAN | 8 | planned | Needs the paid account and Apple's multicast capability. Without it the app shows a plain message. Check phase: the plan gives none |

## Settings

These are the preference keys in `app/src/main/res/xml/preferences.xml` (global settings) and
`app/src/main/res/xml/app_preferences.xml` (per-game settings). The Setting column is the title
users see on Android.

Default column: a value is the `android:defaultValue` in the XML. "set in code" means the XML has
none and the default is in `PreferenceConfiguration`. "n/a" means the row is a button or a link,
so it has no value. "unset" means the per-game setting follows the global one until you override it.

The phase is where the setting's screen is built. Where the feature behind it is built later, the
Notes column says so.

### Basic Settings

| Key | Setting (title) | Default | Phase | Status | Notes |
|---|---|---|---|---|---|
| `list_resolution` | Video resolution | 1280x720 | 3 | planned | |
| `list_fps` | Video frame rate | 60 | 3 | planned | Also fractional and ProMotion rates (phase 2) |
| `seekbar_bitrate_kbps` | Video bitrate | set in code | 3 | planned | |
| `frame_pacing` | Video frame pacing | balanced | 4 | planned | Modes rebuilt on the Metal presenter |
| `jitter_buffer` | Jitter buffer | balanced | 4 | verified | iOS Settings for now (`StarwireJitterBuffer`) |
| `vsync_mode` | V-Sync (Experimental) | off | 4 | planned | Where it applies on iOS |
| `checkbox_sync_lfr` | Sync: LFR (Experimental) | false | 4 | planned | Check: MediaCodec idea |
| `checkbox_async_decode` | Async decode (Experimental) | false | 4 | planned | Check: MediaCodec idea |
| `checkbox_async_lfr` | Async: LFR (Experimental) | false | 4 | planned | Check: MediaCodec idea. Needs async decode |
| `checkbox_ultra_low_latency` | Ultra low latency (Experimental) | false | - | not possible | Vendor decoder flags. VideoToolbox real-time mode is always used |
| `checkbox_stretch_video` | Stretch video to full-screen | false | 4 | planned | |
| `checkbox_auto_resume_stream` | Auto-resume stream after sleep | false | 1 | planned | Check: tied to background and resume handling |

### Audio Settings

| Key | Setting (title) | Default | Phase | Status | Notes |
|---|---|---|---|---|---|
| `list_audio_config` | Surround sound configuration | 2 | 6 | planned | Stereo, 5.1, 7.1 |
| `checkbox_enable_audiofx` | Enable system equalizer support | false | - | not possible | No per-app system audio effects on iOS |
| `checkbox_enable_microphone` | Send my microphone | false | 6 | planned | |
| `list_microphone_target` | Send my microphone to | starwire | 6 | planned | Android values: starwire, host, vban. The `host` value (over the stream) is not built, because Vibeshine lacks it |
| `list_microphone_device` | Microphone | 0 | 6 | planned | Built-in, headset, USB where iOS offers them |
| `microphone_host_info` | Get the Apollo build for microphone | n/a | - | host lacks it | Link to logabell's Apollo build, for the in-stream microphone |
| `vban_setup_info` | Set up the PC | n/a | 6 | planned | Link to the Windows receiver guide |
| `mic_pairing` | Pair with the PC | n/a | 6 | planned | Opens the pairing dialog. Security-sensitive: own review pass |
| `text_vban_stream_name` | VBAN stream name | Stream1 | 6 | planned | Plain VBAN fallback |
| `text_vban_port` | Microphone port | 6980 | 6 | planned | |
| `list_audio_haptics` | Audio haptics | off | 6 | planned | Core Haptics on iPhone and controllers. Not on the iPad itself |
| `seekbar_audio_haptics_intensity` | Audio haptics strength | 100 | 6 | planned | 25 to 200% |

### Gamepad Settings

| Key | Setting (title) | Default | Phase | Status | Notes |
|---|---|---|---|---|---|
| `seekbar_deadzone` | Adjust analog stick deadzone | 7 | 5 | built | |
| `checkbox_multi_controller` | Automatic gamepad presence detection | true | 5 | built | GameController framework |
| `checkbox_usb_driver` | Xbox 360/One USB gamepad driver | true | - | not possible | No raw USB access. Controllers iOS supports still work |
| `checkbox_usb_bind_all` | Override native Xbox gamepad support | false | - | not possible | Needs the USB driver |
| `analog_scrolling` | Use an analog stick to scroll | right | 5 | built | |
| `checkbox_vibrate_fallback` | Emulate rumble support with vibration | false | 5 | built | Core Haptics. iPads have no motor (check) |
| `seekbar_vibrate_fallback_strength` | Adjust emulated rumble intensity | 100 | 5 | built | |
| `checkbox_flip_face_buttons` | Flip face buttons | false | 5 | built | |
| `checkbox_gamepad_touchpad_as_mouse` | Always control mouse with touchpad | false | 5 | built | |
| `checkbox_gamepad_motion_sensors` | Allow use of gamepad motion sensors | true | 5 | built | |
| `checkbox_gamepad_motion_fallback` | Emulate gamepad motion sensor support | false | 5 | built | Uses the device gyro |

### Overlay Menu

| Key | Setting (title) | Default | Phase | Status | Notes |
|---|---|---|---|---|---|
| `overlay_trigger_button` | Menu trigger button | select | 5 | built | Hold a controller button to open the stream menu |
| `overlay_hold_duration` | Trigger button hold duration | 1500 | 5 | built | Milliseconds |
| `checkbox_enable_floating_button` | Floating menu button | true | 5 | verified | |
| `overlay_custom_commands` | Overlay menu commands | n/a | 5 | built | Custom commands. The "Sleep" last step is not possible |
| `import_shortcuts_file` | Import shortcuts from a file | n/a | 5 | built | Files app |
| `clear_imported_shortcuts` | Remove imported shortcuts | n/a | 5 | built | |

### Input Settings

| Key | Setting (title) | Default | Phase | Status | Notes |
|---|---|---|---|---|---|
| `checkbox_touchscreen_trackpad` | Use the touchscreen as a trackpad | true | 5 | verified | Touch modes |
| `checkbox_long_press_right_click` | Long-press to right-click | true | 5 | verified | |
| `checkbox_pinch_to_zoom` | Pinch to zoom anytime | true | 5 | verified | |
| `hide_cursor_mode` | Hide PC cursor | never | 5 | built | Crash-safe ledger. Check host support |
| `seekbar_touch_sensitivity` | Trackpad sensitivity | 100 | 5 | built | |
| `checkbox_keyboard_vibrate` | Keyboard key vibration | true | 5 | built | Core Haptics on iPhone only (check) |
| `checkbox_sticky_modifier_keys` | Sticky modifier keys | true | 5 | verified | |
| `seekbar_keyboard_opacity` | On-screen full keyboard opacity | 90 | 5 | built | |
| `checkbox_mouse_nav_buttons` | Enable back and forward mouse buttons | false | 5 | built | |
| `checkbox_absolute_mouse_mode` | Remote desktop mouse mode | false | 5 | built | |

### On-screen Controls Settings

| Key | Setting (title) | Default | Phase | Status | Notes |
|---|---|---|---|---|---|
| `checkbox_show_onscreen_controls` | Show on-screen controls | false | 5 | verified | |
| `checkbox_vibrate_osc` | Enable vibration | true | 5 | built | Core Haptics on iPhone only (check) |
| `checkbox_only_show_L3R3` | Only show L3 and R3 | false | 5 | built | |
| `checkbox_show_guide_button` | Show Guide Button | true | 5 | built | |
| `seekbar_osc_opacity` | Change opacity | 90 | 5 | built | |
| (no key) | Clear saved on-screen controls layout | n/a | 5 | verified | `ConfirmDeleteOscPreference` has no `android:key`. Reset in the layout editor put the controls back on the iPad 10th gen |

### Host Settings

This category has no key.

| Key | Setting (title) | Default | Phase | Status | Notes |
|---|---|---|---|---|---|
| `checkbox_enable_sops` | Optimize game settings | true | 2 | planned | Check: standard launch option |
| `checkbox_host_audio` | Play audio on PC | false | 2 | planned | Check: standard launch option |
| `virtual_display_mode` | Display on the PC | host | 2 | verified | iOS Settings for now (`StarwireVirtualDisplayMode`): [batch 2](device-runs/2026-10-25-feature-ios-batch-2.md) |
| `checkbox_prevent_packet_loss` | Prevent packet loss | false | 4 | planned | Check: needs a call in Starwire's common-c fork. iOS uses Nonary's fork |
| `checkbox_smart_clipboard_sync` | Automatic clipboard sync | false | - | host lacks it | No `/actions/clipboard` on Vibeshine |
| `checkbox_smart_clipboard_sync_toast` | Show clipboard sync messages | false | - | host lacks it | Needs clipboard sync |
| `checkbox_hide_clipboard_content` | Hide clipboard content | false | - | host lacks it | Needs clipboard sync |

### UI Settings

| Key | Setting (title) | Default | Phase | Status | Notes |
|---|---|---|---|---|---|
| `cover_style` | App covers | missing | 3 | planned | |
| `checkbox_enable_pip` | Enable Picture-in-Picture observer mode | false | 4 | verified | iOS Settings for now (`StarwirePictureInPicture`) |
| `list_languages` | Language | default | 3 | planned | Opens the app's language page in iOS Settings |
| `checkbox_small_icon_mode` | Use small box art | set in code | 3 | planned | Default depends on the device (`getDefaultSmallMode`) |

### Advanced Settings

| Key | Setting (title) | Default | Phase | Status | Notes |
|---|---|---|---|---|---|
| `checkbox_reduce_refresh_rate` | Allow refresh rate reduction | false | 4 | verified | iOS Settings for now (`StarwireReduceRefreshRate`) |
| `text_actual_display_refresh_rate` | Actual display refresh rate | 0 | 4 | built | Detected and shown in the overlay; no way yet to enter one |
| `checkbox_disable_warnings` | Disable warning messages | false | 3 | planned | |
| `video_format` | Change codec settings | auto | 4 | verified | The app's existing codec setting. AV1 needs hardware AV1 |
| `pyrowave_late_frames` | PyroWave late frames | balanced | 7 | planned | |
| `video_renderer` | Video renderer | auto | 4 | planned | Metal or AVSampleBufferDisplayLayer instead of Vulkan or direct |
| `checkbox_custom_vulkan_driver` | Custom Vulkan driver (experimental) | false | - | not possible | iOS apps can't load GPU drivers |
| `text_custom_vulkan_driver_path` | Custom driver file | n/a | - | not possible | |
| `remove_custom_vulkan_driver` | Remove the custom driver | n/a | - | not possible | |
| `checkbox_custom_vulkan_driver_toast` | Driver loaded toast | true | - | not possible | |
| `spatial_dithering` | Spatial Dithering | off | 4 | planned | |
| `checkbox_enable_hdr` | Enable HDR / 10-bit SDR (Experimental) | false | 4 | built | The app's existing HDR setting, now through EDR |
| `checkbox_full_range` | Force full range video (Experimental) | false | 4 | built | iOS Settings for now (`StarwireFullRange`); streams, picture not checked by eye |
| `checkbox_enable_perf_overlay` | Show performance stats while streaming | false | 4 | verified | The app's existing Statistics Overlay setting |
| `checkbox_enable_perf_overlay_lite` | Lite mode | false | 4 | verified | iOS Settings for now (`StarwireOverlay`) |
| `checkbox_enable_post_stream_toast` | Show latency message after streaming | false | 4 | planned | |

### About

| Key | Setting (title) | Default | Phase | Status | Notes |
|---|---|---|---|---|---|
| `about_version` | Version | n/a | 3 | planned | Not saved |
| `about_github` | Starwire on GitHub | n/a | 3 | planned | Link |
| `about_issues` | Report a problem or suggest an idea | n/a | 3 | planned | Link |
| `about_source` | Source code | n/a | 3 | planned | Not saved |
| `about_credits` | Credits | n/a | 3 | planned | Not saved. Credits for copied code are filled in during phase 8 |
| `about_licences` | Open-source licences | n/a | 3 | planned | Not saved |

### Per-game settings

From `app_preferences.xml`. None of these are saved to the global preferences. Each one
overrides the global setting named in Notes. The store is built in phase 1 and the screens in
phase 3, so the phase is 3 for all of them. The Notes say where the feature behind it is later.

| Key | Setting (title) | Default | Phase | Status | Notes |
|---|---|---|---|---|---|
| `checkbox_use_global_settings` | Use Global Settings | true | 3 | planned | Hard-coded English title on Android, not a string resource. Fix for iOS |
| `list_app_resolution` | Video resolution | unset | 3 | planned | Overrides `list_resolution` |
| `list_app_fps` | Video frame rate | unset | 3 | planned | Overrides `list_fps` |
| `text_app_bitrate_kbps` | Video bitrate | unset | 3 | planned | Overrides `seekbar_bitrate_kbps`. Entered in Mbps |
| `list_app_frame_pacing` | Video frame pacing | unset | 3 | planned | Overrides `frame_pacing`. Pacing itself is phase 4 |
| `game_jitter_buffer` | Jitter buffer | unset | 3 | planned | Overrides `jitter_buffer`. Buffer itself is phase 4 |
| `text_app_actual_display_refresh_rate` | Actual display refresh rate | unset | 3 | planned | Overrides `text_actual_display_refresh_rate` |
| `list_app_enable_hdr` | Enable HDR / 10-bit SDR (Experimental) | unset | 3 | planned | Overrides `checkbox_enable_hdr`. HDR itself is phase 4 |
| `list_app_enable_perf_overlay` | Show performance stats while streaming | unset | 3 | planned | Overrides `checkbox_enable_perf_overlay` |
| `game_video_format` | Change codec settings | unset | 3 | planned | Overrides `video_format` |
| `game_vsync_mode` | V-Sync (Experimental) | unset | 3 | planned | Overrides `vsync_mode` |
| `game_checkbox_sync_lfr` | Sync: LFR (Experimental) | unset | 3 | planned | Overrides `checkbox_sync_lfr`. Check, as for the global setting |
| `game_checkbox_async_decode` | Async decode (Experimental) | unset | 3 | planned | Overrides `checkbox_async_decode`. Check, as for the global setting |
| `game_checkbox_async_lfr` | Async: LFR (Experimental) | unset | 3 | planned | Overrides `checkbox_async_lfr`. Check, as for the global setting |
| `game_virtual_display_mode` | Display on the PC | unset | 3 | planned | Overrides `virtual_display_mode`. Launch option is phase 2 |
| `game_checkbox_touchscreen_trackpad` | Touch mode | unset | 3 | planned | Overrides `checkbox_touchscreen_trackpad`. Touch modes are phase 5 |
| `game_hide_cursor_mode` | Hide PC cursor | unset | 3 | planned | Overrides `hide_cursor_mode`. Feature is phase 5 |
| `game_list_audio_haptics` | Audio haptics | unset | 3 | planned | Overrides `list_audio_haptics`. Feature is phase 6 |

## Notes for checking

- Keys that are only a category or screen, left out of the tables:
  - `preferences.xml`: `category_basic_settings`, `category_audio_settings`,
    `category_gamepad_settings`, `category_overlay_menu`, `category_input_settings`,
    `category_onscreen_controls`, `category_ui_settings`, `category_advanced_settings`,
    `category_about`.
  - `app_preferences.xml`: `category_app_specific`.
  - `category_help` appears only inside an XML comment (the Help category is switched off), so it
    is not a live key and isn't listed.
  - The Host Settings category has no key.
- One real setting has no key: the "Clear saved on-screen controls layout" button
  (`ConfirmDeleteOscPreference`). It has its own row.
- Per-game settings in `app_preferences.xml` are saved by `AppStreamSettings`, so they are not
  in the global preferences.
- Not in the XML files but in the README or the plan, so they are in the Features table only:
  Quick Launch, the stream menu, Pencil, external display, frame interpolation, Remote Monitor
  and Terminate tiles, sleep the PC, hardware metrics, App Intents and Wake-on-LAN.
