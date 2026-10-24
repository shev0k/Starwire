# Device run: <branch>, <YYYY-MM-DD>

Copy this file to `<YYYY-MM-DD>-<branch with / as ->.md` and fill in every field, following
[the Mac runbook](../mac-runbook.md). Write "not checked" for anything you didn't do, and say why.

## What was run

| | |
| --- | --- |
| Date and time (UTC) | |
| Branch and commit | `feature/...` at `<first 10 characters of the hash>` |
| Who ran it | Claude Code on the Mac, or a person |
| Mac | model, macOS version |
| Xcode | version and build (`xcodebuild -version`) |
| XcodeGen | version |
| iPad | model, iPadOS version |
| Bundle ID and signing | `io.github.shev0k.starwire`, free personal team (or what was used instead) |
| Build configuration | Release or Debug |
| PC and host | Vibeshine version, GPU, display and refresh rate |
| Network | iPad on Wi-Fi (band, for example 5 GHz or 6 GHz), PC wired or Wi-Fi |

## Build and install

| Step | Result | Notes |
| --- | --- | --- |
| Submodules and `xcodegen generate` | pass / fail | |
| Device build | pass / fail | warnings worth noting |
| Installed over the old copy (not deleted) | yes / no | |
| Pairing kept after install | yes / no / first install | |
| App starts | yes / no | |

## Tests

| Test | Result | Notes |
| --- | --- | --- |
| `swift test` for StarwireKit | n passed, n failed | |
| Simulator build | pass / fail | |
| App tests on the iPad | none yet / n passed, n failed | |

## Stream

| | |
| --- | --- |
| App streamed | Desktop |
| Resolution and frame rate asked for | |
| Codec, HDR, chroma | HEVC, off, 4:2:0 |
| Bitrate | |
| Length of the stream | |
| Frame rate shown, start and end | |
| Dropped frames (network, pacing) | |
| Decode time | |
| Network latency | |
| Visible problems | stutter, tearing, artefacts, audio gaps, input lag |
| Background and resume | worked / crashed / hung |
| Stopping the stream | clean / crashed / hung |

Screenshots: list the files next to this report.

## Problems

Each problem: what happened, what you did just before, how often, and the log lines that show it.

## Parity rows this run verifies

Rows of [parity.md](../parity.md) that this run showed working on the iPad. Only these may change
to `verified`, with a link to this report.

## Changes to the runbook

What was wrong or missing in the runbook, and what was changed.
