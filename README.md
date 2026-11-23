# Wick

A small tvOS player built on [AetherEngine](https://github.com/superuser404notfound/AetherEngine) that Lampa can use as an external player for torrent streams.

**Status: version 0.2.0 compiles and runs on a real Apple TV.** It is developed on Windows and built on a GitHub macOS runner, then sideloaded with atvloadly.

## How Lampa reaches it
Lampa has no hook to register a new player. On Apple TV it picks a URL template from its player setting and opens it with `window.location.assign(...)`. The torrent player list is `tvospro`, `tvos`, `tvosSelect`, `vlc`, `infuse`, `senplayer`, `vidhub`, `inner`, `svplayer`. This app registers the URL scheme of one of them:

| Lampa setting | URL Lampa opens | Registered here |
|---|---|---|
| **SenPlayer** | `SenPlayer://x-callback-url/play?url=<encoded stream URL>` | yes (default) |
| VLC | `vlc-x-callback://x-callback-url/stream?url=...` | no (edit `project.yml` to use it) |
| VidHub | `open-vidhub://x-callback-url/open?url=...` | no (use it only if the real VidHub is not installed) |

Also accepted: `wick://play?url=...&title=...&position=...&sub=...&x-success=...&x-error=...&x-cancel=...&return=...`, and Infuse-style links with `position`, `filename`, `sub`, `x-success`, `x-error`.

**Do not install the real SenPlayer** next to this app: tvOS would pick one of the two for that scheme.

### Choosing which player to announce as
tvOS reads an app's URL schemes from its `Info.plist` at install time, so an app cannot switch them while running. Instead, `tools/set_schemes.py` rewrites them inside the `.ipa` in seconds, on Windows, with no rebuild:

```bash
python tools/set_schemes.py Wick.ipa Wick_vlc.ipa vlc
python tools/set_schemes.py Wick.ipa out.ipa senplayer svplayer   # several at once
```

| Name | Scheme Lampa opens |
|---|---|
| `vlc` | `vlc-x-callback` |
| `infuse` | `infuse` |
| `senplayer` | `senplayer` |
| `vidhub` | `open-vidhub` |
| `svplayer` | `svplayer` |

Then upload the new IPA to atvloadly (reinstalling over the old one). The Settings screen lists the names the installed build answers to. Claim only players whose real app is **not** installed. `inner` is Lampa's built-in web player and has no URL scheme, so it cannot be claimed this way; it would need a Lampa plugin that intercepts playback.

What Lampa sends in each case: the plain templates carry **only the stream URL**. No title, subtitles or position. Only Infuse links carry those. So this app:
- derives a title from the file name,
- remembers the last position per stream itself (`ResumeStore`, "Resume where I stopped" in Settings),
- reads subtitles and audio tracks from the file.

Lampa's `&preload` flag on TorrServer links is rewritten to `&play`, as Lampa does for Infuse.

## Settings (stored on the device, read at each playback)
They map onto real `LoadOptions` fields of the engine.

| Setting | Engine field |
|---|---|
| Dolby Vision (on / HDR10 base layer only) | `dolbyVisionHandling` |
| Dolby Vision FEL: off / enhanced conversion / full dual-layer (software host) / full dual-layer (AVPlayer output) | `foldsDolbyVisionFEL`, `preferDualLayerDolbyVision`, `dualLayerRoute` |
| TrueHD / DTS:X Atmos: off, or render to 5.1.2 / 5.1.4 / 7.1.2 / 7.1.4 / 9.1.6 | `objectAudioRendering` (`.render(layout)`) |
| Bridge for TrueHD / DTS / Opus: compatible surround or lossless | `audioBridgeMode` |
| Audio delay, preferred audio and subtitle language | `audioDelaySeconds`, `preferredAudioLanguages`, `preferredSubtitleLanguages` |
| Upscale low-resolution video, line-art upscaler | `upscalesLowResolutionVideo`, `upscaleScaler` |
| Skip step, resume, subtitle size, debug info, where to return to | app only |

Defaults: FEL = enhanced conversion (the engine default), Atmos = render to **5.1.2**.

Notes from the engine docs:
- FEL, TrueHD and DTS:X need optional components ("package traits"). `HostDeps/Package.swift` switches on `TrueHDObjectAudio`, `DTSXObjectAudio`, `DualLayerDolbyVision`, `DolbyVisionFelCurves`. The Settings screen shows which ones are really in the build and warns when a chosen setting would do nothing. The engine warns that some of these components "may be subject to third-party patent licensing"; check that this is acceptable for your use. Delete a trait from that file to leave it out.
- Full dual-layer FEL on the software host decodes Atmos (E-AC-3 JOC) as its 5.1/7.1 core, without the objects. The AVPlayer-output route keeps AVPlayer's audio. The engine docs say it "has not been run on tvOS", but it passed Wick's Profile 7 FEL test on a real Apple TV.
- The dual-layer route only takes streams up to UHD at 30 fps plus a 1080p enhancement layer; anything heavier silently keeps the normal route.
- Settings apply to the next playback. During playback, press ▲ or ▼, then "Reload with current Settings" (`reloadAtCurrentPosition(applying:)`).

## Remote control and screens
The look follows a tvOS-style design (glass panels, white focus capsules). It was drawn from photos of a similar player plus its public layout notes; no code was copied.

While playing:
- ◀ ▶ skip (the step grows with quick repeats; set the length in Settings), Select or Play/Pause toggles pause.
- ▲ shows the round buttons at the bottom right: **Subtitles**, **Audio**, **Playback**. Select opens a glass menu (arrows move, ◀ ▶ adjust a Delay row, Menu goes back).
  - Subtitles: On / Off, Language, Size, Delay.
  - Audio: Delay, then the audio tracks.
  - Playback: Speed, Dolby Vision FEL, Height Speakers, Upscale, and "Apply changes now" (reloads at the current position).
- ▼ opens the **Info** and **Details** panes (◀ ▶ switches). Details shows video, audio and decode/stream facts read from the engine.
- Menu hides the bar; Menu again leaves the player and opens `lampa://` (or the return address in the link, or stays, see Settings).

Settings (the home screen of the app) are two columns: Playback, Video, Audio, Subtitles, Lampa, About.

## Build
Needs macOS and Xcode (the engine's README says Xcode 27). CI does this:

1. Put a **private** copy of this repository on GitHub (the workflow is in `.github/workflows/build-ipa.yml`).
2. Run the workflow "Build unsigned IPA" (also runs on push to `main`).
3. Download the `Wick-ipa` artifact → `Wick.ipa`. If the build fails, the `build-log` artifact has the full log.

The workflow publishes the IPA only from a private repository. No prebuilt IPA is offered here, because the build can include components that may need patent licenses.

Locally on a Mac: `brew install xcodegen && xcodegen generate`, then open `Wick.xcodeproj`.

## Install
1. In the atvloadly web UI, choose your Apple TV, upload `Wick.ipa` and install it with your Apple ID.
2. A free Apple ID allows **3 active sideloaded apps**. atvloadly refreshes them on its schedule.
3. In Lampa: Settings → Player → the Apple TV torrent player → **SenPlayer**.
4. Start a torrent movie in Lampa. Lampa opens this app.

## Test checklist
- [x] CI builds
- [x] IPA installs and the app runs on a real Apple TV
- [x] Lampa → SenPlayer opens the app and playback starts from a TorrServer URL
- [x] **Seeking works** on an `http://…/stream/…mkv?link=…&play` URL
- [x] Audio and subtitle switching, PGS bitmap subtitles in the right place
- [x] HDR10 / Dolby Vision triggers the TV's mode switch (tvOS "Match Content")
- [x] TrueHD Atmos with "Render to 5.1.2" reaches the receiver as Atmos
- [x] A Profile 7 FEL title in each FEL mode
- [x] Menu returns to the Lampa app (`lampa://` may not be handled by every Lampa client; if not, pick "Stay in this app")
- [x] The app refreshes at the next atvloadly window

## Notes and open questions
- `Info.plist` is generated by XcodeGen. App Transport Security is opened fully (`NSAllowsArbitraryLoads`) because TorrServer is plain http on the LAN.
- The engine is pinned to **7.64.0**, the version tested on a real Apple TV. Version 7.73.0 fails to compile with Xcode 26.6 (the compiler times out type-checking `PerFrameBenchmark.swift`), so test a newer engine before raising the pin in `HostDeps/Package.swift`.

## License
Wick's own code is under the [MIT License](LICENSE). AetherEngine (LGPL-3.0 with an App Store exception) and FFmpeg (LGPL, embedded dynamically) keep their own licenses and are not covered by it. AetherEngine's docs do not mention sideloaded apps, so review these terms before distributing a built IPA.
