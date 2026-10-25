# iOS batch 4.5: UX, settings and quality of life

Written 25 Oct 2026 on `feature/ios-batch-4-5`, after the owner tried batch 4. This page is the
gap list and the plan. What was built and tested is in the batch's device report and in
[parity.md](parity.md).

## What done looks like

- The owner sees a new stream menu, menu button, settings layout, on-screen keyboard and a
  controller keyboard, and can reach every setting that makes sense mid-stream from the menu.
- Settings has every touch mode, a typed bitrate, the iPad's own resolutions and the picture's
  fit, gestures, keyboard options. Old settings carry over (unit tests).
- Scrolling with a finger is measured on the iPad before and after the fix, in every touch mode.
- Docs: this page, parity.md, the CHANGELOG and a device report.

## Audit: Android, iOS settings and the iOS stream menu

The full tables are in the session notes (`ios-batch-4-5-settings-audit.md`); the short version:

- **Settings mirror Android.** Every Android key is in `SettingsCatalog` with Android's default,
  and a test parses `preferences.xml` to keep it so. All 17 per-game overrides exist.
- **Shown but not used yet** (stored, nothing reads them): `frame_pacing`, `vsync_mode`,
  `checkbox_sync_lfr`, `checkbox_async_decode`, `checkbox_async_lfr`, `checkbox_stretch_video`,
  `checkbox_auto_resume_stream`, `checkbox_prevent_packet_loss`, `pyrowave_late_frames`,
  `spatial_dithering`, `checkbox_disable_warnings`, `checkbox_enable_post_stream_toast`,
  `text_actual_display_refresh_rate`, `checkbox_gamepad_motion_sensors`. Most are planned in
  parity.md; this batch wires the ones with an iOS meaning (below).
- **Touch mode:** settings and games choose only trackpad or direct
  (`checkbox_touchscreen_trackpad`). The other four modes are in the menu only, for one stream.
- **Bitrate:** a slider plus a typed value hidden behind "custom". It doesn't follow resolution
  and frame rate changes as Android's does.
- **Resolution:** 720p, 1080p, 1440p, 4K or custom. The old screen's Safe Area and Full Screen
  choices went with the storyboards, so the iPad's own size can only be typed. Stretch is a
  switch that does nothing.
- **Stream menu:** has every Android tile except clipboard, PC commands and rotate (Vibeshine has
  no clipboard or commands; iOS rotates by itself) and the left-edge brightness slider. No
  settings can be changed from it except bitrate, touch mode and sensitivity.
- **Menu button:** on or off, dragged anywhere; nothing else.
- **On-screen keyboard:** opacity, sticky modifiers, key vibration. One layout (Android's).
- **Gestures:** three-finger tap for the menu, fixed. In multi-touch mode there is none.
- **Export** from Settings leaves out per-game settings.

## Reference clients

From the notes (`ios-batch-4-5-reference-qol.md`), what is worth taking:

- **Nothing on the wire says a PC text field has focus.** Vibeshine's control messages stop at
  0x5503 and none is about the keyboard; VoidLink and Artemis open keyboards by hand only. So
  auto-opening the keyboard needs the Windows helper (item 8 below).
- **Scroll packets aren't merged.** moonlight-common-c sends one reliable packet per scroll call
  to Sunshine and Vibeshine, while it sums relative mouse moves and keeps only the last absolute
  position. Touch moves go unreliable, one per call. Coalesced touches: no client uses them for
  fingers.
- VoidLink: the iPad's own sizes as resolution choices (full window and safe area, from the real
  screen), auto-docking widgets (17 pt peek, 0.8 then 0.2 alpha), finger-count taps for the
  keyboard, inertia for two-finger scroll, hardware keyboard shortcuts.
- Artemis: a folded control bar that fades after 5 s; scroll remainders kept; real key events,
  with Unicode text only for characters with no US key.
- Vibelight: an invisible text responder that works with split and floating system keyboards.
- moonlight-switch and imoonlight: the only controller keyboards, as design references.

## Plan

Logic goes in StarwireKit with recording-sink tests; the app draws it. In order:

1. **Measure scrolling** (no host change): `TouchRateMeter` (touch deliveries, coalesced samples,
   delivery delay, packets per second per gesture) and `InputLatencyProbe` (input to picture, and
   how often the PC's page moved, read from two squares on `ios/scripts/input-latency.html`).
   Device test `testScrollSmoothness` runs every touch mode.
2. **Fix scrolling** from what the numbers say. Known already: the natural trackpad throws away
   the fraction of every scroll step, so slow scrolls stall.
3. **Settings:**
   - Touch mode: all six, in Settings and per game (`list_touch_mode`, migrated from
     `checkbox_touchscreen_trackpad`).
   - Bitrate: a typed Mbps field next to the slider, and "follow resolution" until moved.
   - Resolution: "This iPad, full screen" and "This iPad, safe area" from the real screen, the
     presets, and custom. Picture: fit, stretch or fill. Vibeshine's scale factor per game too.
   - Gestures, menu button, on-screen keyboard and controller keyboard sections.
   - Export with per-game settings.
4. **Stream menu:** grouped, with quick toggles and the settings that apply mid-stream, by touch
   and controller.
5. **Menu button:** look, size, opacity, docking to an edge, auto-hide.
6. **Gestures:** four- and five-finger taps (defaults: full keyboard, menu), configurable, working
   over multi-touch passthrough. iPadOS takes four- and five-finger swipes and pinches when its
   multitasking gestures are on, so the defaults use taps only.
7. **On-screen keyboard:** size, opacity, docked or floating (drag to move), layout presets and a
   key remapping editor, saved in the settings store.
8. **Auto-open keyboard:** needs the Windows helper to watch for a focused text field (UI
   Automation) and tell the iPad over the SWMC channel. Security-sensitive: the owner decides
   before anything is built.
9. **Controller keyboard:** a grid for the d-pad or stick, L1 backspace, R1 space, L2 shift, R2
   symbols, Start sends Enter, B closes. Opens instead of the touch keyboard when a controller was
   the last input.
10. **Covers** for the three test apps: `ios/scripts/covers/`, image paths only, apps.json backed
    up first.

Design checkpoint: quick versions of the menu, the button, the settings layout and both keyboards
go to the owner as iPad screenshots before the full versions.
