# Droppy Parity Plan — `Nytuo/boring.notch` @ `dev`

Implementation plan to close the remaining gap to Droppy. Written to be handed to Claude Code.

- **Target:** `github.com/Nytuo/boring.notch`, branch **`dev`**, audited at **`57415fc`** (`ci: build without creds`, 1 behind `dev` head `c7d374c`)
- **Reference product:** Droppy (getdroppy.app), macOS 14+, one-time $9.99, ~27 "Droplets"
- **Supersedes** the earlier plan written against `main`. That plan is void — roughly 60% of it is already implemented here.

---

## 0. What changed since the `main`-based plan

`dev` is 219 commits ahead of `main`. Your own commit `8997844 feat: adding boring features` (28 Jul 2026) added 66 files and ~14,100 lines. It already ships:

- **An extension system** — `ExtensionSystem/ExtensionAPI.swift`, `ExtensionRegistry.swift`, `BuiltInExtensions.swift`: manifest, capability set, lifecycle, per-extension settings surface, settings gallery, nine built-ins registered.
- **A layout system** — `models/NotchLayout.swift` with `NotchHeaderItem`, `NotchTabItem`, order persisted in `Defaults`, reconciliation of stored order against current cases, and header/tab shadowing logic.
- **Clipboard manager** — polling, hashing, pinning, search, exclusions, confidential-type handling, optional persistence.
- **Weather** — manager + service + models + settings, location modes, units, hourly/daily.
- **Notification watcher** — Accessibility-tree based, with permission and unsupported-layout states.
- **Clock** — timer, stopwatch, laps, analog face, closed-notch display, timer sound.
- **System stats, App switcher, Bluetooth (incl. device battery), Caffeine, Downloads (Safari/Chromium/Firefox), Screenshot catcher, Lock screen widgets, Function buttons.**
- **Synced lyrics** via LRCLIB (`managers/LyricsService.swift`, LRC parsing, timed lookup).
- **Real-time audio waveform** (`AudioCaptureManager`), OSD subsystem restructured with **Lunar and BetterDisplay integration**.

That is already past several paid competitors. This plan covers only what's actually left.

---

## 1. Ground rules

### 1.1 Clean-room only

Droppy is closed, paid software. Reimplementing feature *ideas* is fine; the following is not: decompiling the binary or its Droplet bundles, copying icons/animations/sounds/copy, or reusing their product names — "Droplet", "Basket", "TermiNotch", "Mechey", "Droppy Cloud", "The Trench" are theirs.

You already have your own vocabulary in the code. **Keep using it.** New features extend the existing nouns rather than introducing parallel ones:

| Concept | Your existing term — use this |
| --- | --- |
| Feature unit with lifecycle + toggle | `BoringExtension` / `ExtensionRegistry` |
| What a feature contributes | `ExtensionCapability` |
| Notch destination | `NotchTabItem` → `NotchViews` |
| Header accessory | `NotchHeaderItem` |
| Lock screen tile | `LockScreenWidget` |

For the two genuinely new concepts below, suggested names: **Catcher** (Droppy's Basket) and **Console** (Droppy's TermiNotch).

### 1.2 Fork discipline

You track an active upstream and merge `main` into `dev` regularly (`f137008`, `4f94c8a`). Every edit to an upstream file is future conflict surface, and there's already a lot of it — `ContentView.swift` +261, `BoringHeader.swift` +128, `Constants.swift` +136, `BoringViewCoordinator.swift` +84.

Going forward: new features add files under their own directory and register through `ExtensionRegistry`. Where an upstream file must change, make it a single call, not inline logic. Keep a `FORK_NOTES.md` mapping every touched upstream file to a reason — rebases will get painful otherwise.

### 1.3 Non-goals

App Store distribution · running a hosted cloud service · matching Droppy's visual design.

---

## 2. Baseline audit — `dev` @ `57415fc`

### 2.1 Structure

```
boringNotch/
  ExtensionSystem/          ExtensionAPI, ExtensionRegistry, BuiltInExtensions   ← the backbone
  models/                   NotchLayout (header items + tabs + resolver), FunctionButton,
                            WeatherModels, Constants (~160 Defaults keys), BoringViewModel …
  managers/                 AppSwitcher, AudioCapture, BatteryActivity, Bluetooth, Caffeine,
                            Calendar, Clipboard, Clock, Download, Image, Lyrics, Music,
                            NotchSpace, NotificationWatcher, Screenshot, SystemStats,
                            Weather, WeatherService, Webcam
  components/               AppSwitcher, Bluetooth, Caffeine, Calendar, Clipboard, Clock,
                            FunctionButtons, Live activities, LockScreen, Music, Notch,
                            Notifications, OSD/{Managers,Models,Views}, Onboarding,
                            Screenshots, Settings/Views/*, Shelf/{Models,Services,ViewModels,Views},
                            SystemStats, Tabs, Weather, Webcam
  MediaControllers/         protocol + NowPlaying, AppleMusic, Spotify, YouTube Music
  observers/ extensions/ helpers/ enums/ utils/ sizing/ private/ Shortcuts/ XPCHelperClient/
BoringNotchXPCHelper/       non-sandboxed XPC service: accessibility auth, keyboard/screen
                            brightness, Lunar event stream + OSD suppression
```

### 2.2 Constraints that still shape everything

**(a) The app is sandboxed**, now with more entitlements than `main`: audio-input, bluetooth, location, pictures read-only, downloads read-only, calendars, camera, bookmarks, network client/server, Apple Events for Spotify/Music.

**(b) The XPC helper is not sandboxed** and has grown to ~18 methods. It is the only route to Accessibility control of other processes, event taps, PTYs, and privileged capture.

**(c) The helper accepts any incoming connection.** `main.swift`'s `shouldAcceptNewConnection` configures interfaces and returns true with no code-signature or team-ID validation. That was defensible when the helper only set brightness. Several features below (keystroke posting, PTY spawn, window control) would turn it into a local privilege-escalation primitive. **This is now blocking work, not cleanup — see F-01.**

### 2.3 Seams to build on

- `ExtensionRegistry.registerBuiltInExtensions()` — one line per new feature.
- `NotchLayoutResolver.reconcile(_:all:)` — already handles added/removed cases in a stored order. New tabs and header items get migration for free.
- `NotchTabItem.headerCounterpart` / `isShadowedByHeaderItem` — the rule that a header icon suppresses the duplicate tab. Respect it for anything new that wants both.
- `NotchViews.openSize` / `hugsContent` — the sizing contract for new destinations.
- `FunctionButtonAction` — enum of sandbox-safe actions; the natural home for new one-tap actions (F-15, F-21, F-23).
- `Shelf/{Models,Services,ViewModels,Views}` — the cleanest structure in the repo. Copy its shape.
- `LyricsService` — provider pattern already proven against an external API with caching.

### 2.4 Debt worth naming

- `models/Constants.swift` is ~160 keys in one extension. New features should declare their keys in their own files (`Defaults.Keys` is extensible from anywhere) or that file becomes unmaintainable.
- `ContentView.swift` and `BoringViewCoordinator` are absorbing per-feature state. New features should own state in their manager.
- `BoringExtension.isEnabled` deliberately proxies each feature's existing `Defaults` key — good call, keep it. But the manifest has no permissions declaration yet (F-02).
- No unit tests exist for any of the new managers.

---

## 3. Gap matrix vs Droppy

✅ shipped · 🟡 partial · ❌ missing

| Droppy capability | Status on `dev` |
| --- | --- |
| File tray / shelf with AirDrop | ✅ |
| Clipboard manager, search, pinboard | ✅ |
| Media controls, multi-source | ✅ |
| Live synced lyrics | ✅ (LRCLIB) |
| Volume / brightness HUDs | ✅ (+ Lunar & BetterDisplay — beyond Droppy) |
| Calendar & reminders | ✅ |
| Weather | ✅ |
| Timers | ✅ (+ stopwatch) |
| Notification feed | ✅ (AX-based) |
| Battery activity | ✅ (+ charging wattage) |
| Bluetooth activity + device battery | ✅ |
| Downloads | ✅ (3 browsers) |
| Screenshot catcher | ✅ |
| Lock screen widgets | ✅ |
| Extension system + gallery | ✅ |
| Keep-awake | ✅ (no Droppy equivalent) |
| System stats | ✅ (no Droppy equivalent) |
| App switcher | ✅ |
| Custom shelf/board layout | 🟡 ordered lists, not a drag-and-drop grid — **F-11** |
| Dynamic Island on notchless Macs | 🟡 `Style.floating` declared, never used — **F-04** |
| Screenshot editor | 🟡 catcher only, no annotation — **F-12** |
| Pomodoro | 🟡 timer exists, no cycles — **F-13** |
| Inline notification reply | 🟡 read-only watcher — **F-31** |
| Cloud share links | 🟡 local QuickShare providers — **F-51** |
| Playing Next / queue | ❌ **F-20** |
| AirPlay / audio output picker | ❌ **F-21** |
| Catcher (jiggle-drag tray) | ❌ **F-10** |
| Universal launcher | ❌ **F-14** |
| Emoji picker | ❌ **F-15** |
| Window snapping | ❌ **F-30** |
| Terminal in the notch | ❌ **F-33** |
| Keystroke sounds | ❌ **F-32** |
| Voice recorder + transcription | ❌ **F-40** |
| AI background removal | ❌ **F-41** |
| File conversion | ❌ **F-42** |
| Motion art | ❌ **F-43** |
| VPN status | ❌ **F-22** |
| Low Power Mode toggle | ❌ **F-23** |
| Meeting controls | ❌ **F-24** |
| AI agent progress (Claude/Codex/Cursor) | ❌ **F-25** |
| Natural-language calendar entry | ❌ **F-50** |
| Third-party add-ons | ❌ **F-52** |

**19 real gaps, plus 4 infrastructure items you'd want regardless.**

Effort scale: **S** <½ day · **M** 1–3 days · **L** ~1 week · **XL** 2+ weeks.

---

## 4. Phase 0 — Foundations (first)

### F-01 — Harden the XPC helper, add capability gating · **M** · blocking

Half the remaining features need privileged operations. Before adding any of them:

1. **Validate the client** in `shouldAcceptNewConnection`: resolve the peer with `SecCodeCopyGuestWithAttributes` on its `processIdentifier`, then `SecCodeCheckValidity` against a requirement string pinning your signing identity. Reject otherwise, with a `#if DEBUG` bypass for unsigned local builds.
2. **Add capability gating.** Group new methods by capability, each mirrored to a user-facing setting the helper re-reads before every call:

   | Capability | Methods | Feature |
   | --- | --- | --- |
   | `axWindows` | `listWindows`, `setWindowFrame`, `focusWindow` | F-30 |
   | `axNotifications` | `invokeNotificationAction(_:text:)` | F-31 |
   | `input` | `postKeystroke(_:modifiers:)`, `startEventTap`, `stopEventTap` | F-15, F-24, F-32 |
   | `pty` | `spawnShell`, `write`, `resize`, `terminate` | F-33 |
   | `power` | `setLowPowerMode` | F-23 |

3. **Log every privileged call** — operation name only, never arguments containing user content.
4. **Never accept a path, command string, or arbitrary key sequence from outside validated app code.** No pass-through `exec`.

**Acceptance:** an unsigned third-party process cannot obtain the helper's interface; each capability refuses when its setting is off; existing brightness/Lunar paths unaffected.

### F-02 — Extension manifest: permissions + storage decision · **S**

`ExtensionManifest` describes capabilities but not *permissions*. Add `requiredPermissions: Set<Permission>` (accessibility, screenRecording, microphone, speech, location, fullDiskAccess, inputMonitoring, automation(bundleID)) and render them in the extensions gallery, so enabling a feature discloses what it will ask for **before** the TCC prompt appears.

Pair it with one `PermissionsManager` owning request + status + a deep link to the right System Settings pane, extending the existing `PermissionsRequestView` onboarding rather than replacing it.

**Also decide storage.** Clipboard, notifications, and soon recordings and transcripts are append-heavy and searchable, currently persisted ad-hoc. Recommend adding **GRDB** and moving clipboard + notification history to SQLite in Application Support, with blobs content-addressed on disk. Ship a Privacy pane listing every store, its size, its retention, and one wipe button.

### F-03 — Unified live-activity arbitration · **M**

Many things now compete for the closed notch: music, battery, downloads, Bluetooth, notifications, caffeine countdown, clock, system stats — plus everything in this plan. `BoringViewCoordinator`'s `sneakPeek` / `expandingView` pair wasn't designed for that many claimants.

Introduce a `LiveActivityCenter` with a priority queue:

```swift
struct LiveActivity: Identifiable {
    let id: String            // "clock.timer" — resubmitting replaces
    let owner: String         // extension manifest id
    var priority: Priority    // .ambient < .informational < .transient < .urgent
    var lifetime: Lifetime    // .sticky | .timed(TimeInterval)
    var leading: AnyView
    var trailing: AnyView
    var expanded: AnyView?
    var onTap: (() -> Void)?
}
```

Highest priority wins; ties go to most recent; `.sticky` claimants (running timer, VPN connected, caffeine active) reappear when transients expire. Migrate producers one at a time behind `Defaults[.useActivityBusV2]`, keeping the old path for one release. Do this before F-22 and F-25, which each add another persistent claimant.

**Acceptance:** a documented priority table; volume HUD + running timer + charging event + Bluetooth connect submitted at once behave deterministically and as documented.

### F-04 — Island mode for notchless displays · **M**

`Style.floating` exists in `enums/generic.swift` and is referenced nowhere. "Notch or not" is Droppy's core pitch, and this is the last structural gap.

Resolve a presentation style per display: notched built-in → `.notch`; external/notchless → `.floating` (a rounded pill pinned under the menu bar, with position and width settings). Add `IslandShape` beside `NotchShape`, make `sizing/matters.swift` style-aware, and ensure **no feature view knows which style it's in**.

**Acceptance:** on an external 27", the pill appears, hover-expands, hosts every tab, and accepts shelf drops; a mixed notched + notchless setup behaves correctly on both.

---

## 5. Phase 1 — Finish the half-built

### F-10 — Catcher (jiggle-to-summon drop target) · **M**

Droppy's "grab, jiggle, drop". Extend `observers/DragDetector.swift`: during an active drag, keep a 500 ms ring buffer of mouse positions and detect ≥3 horizontal direction reversals with amplitude >40 pt within 600 ms. On trigger, spring the notch open to the shelf, register the drop target, auto-close ~2 s after the drop or on cancel.

**Files:** `observers/ShakeGestureRecognizer.swift`, `components/Shelf/Services/CatcherPresenter.swift`.
**Defaults:** `catcherEnabled`, `catcherSensitivity`, `catcherAutoCloseDelay`.
**Acceptance:** ≥95% detection on deliberate shakes; ≤1 false positive per hour of ordinary dragging (measure it); no interference with `expandedDragDetection`.

### F-11 — Drag-and-drop board · **L**

`NotchLayout` gives ordering; Droppy gives a grid you compose. Build on what's there rather than replacing it: add a `BoardLayout` (widget id → position + size class `.small`/`.wide`/`.large`), persisted **per screen UUID** (`NSScreen+UUID.swift` exists), reconciled through the same `NotchLayoutResolver.reconcile` pattern.

Edit mode: a pencil button in `BoringHeader` → jiggle (`Pow` is already a dependency), drag to reorder with `matchedGeometryEffect`, `+` sheet listing widgets from enabled extensions, `−` to remove. Add `boardWidgets() -> [BoardWidgetDescriptor]` to `BoringExtension` with a default empty implementation so existing extensions don't break.

**Acceptance:** add/remove/reorder/resize; per-display layouts; survives relaunch; auto-heals when a feature providing a placed widget is disabled.

### F-12 — Screenshot editor · **M**

`ScreenshotManager` catches and previews; there's no annotation. Add an editor sheet: crop, arrow, box, freehand, text, blur/pixelate (CoreImage `CIPixellate` over a mask), then save-in-place / copy / add-to-shelf. Optionally add interactive capture by shelling `screencapture -i` through the helper — simpler and more native than a ScreenCaptureKit picker.

### F-13 — Pomodoro · **S**

`ClockManager` already has a wall-clock-deadline timer, pause/resume, and a finish notification. Add a cycle layer on top: work / short break / long break durations, cycle count, auto-advance, session history. No new engine.

### F-20 — Playing Next (queue) · **M**

Extend `MediaControllerProtocol` with **optional** `queue() async -> [QueueItem]?` and `playItem(at:)`. Apple Music and Spotify expose queue over AppleScript/ScriptingBridge (entitlements already cover both); Now Playing does not — return `nil` and hide the UI rather than fabricate it. Surface as a list in `NotchPlayerView` beneath the controls.

### F-21 — Audio output picker · **M**

CoreAudio (`kAudioHardwarePropertyDevices`, `kAudioHardwarePropertyDefaultOutputDevice`) for enumeration and switching — `components/OSD/Managers/XPC/VolumeManager.swift` already talks to CoreAudio, so extend rather than start fresh. AirPlay targets are **not** publicly enumerable; present a system routing picker (`AVRoutePickerView`) for those and say so plainly. Add as a header accessory or a player row, plus a `FunctionButtonAction` case for cycling outputs.

---

## 6. Phase 2 — New activities

### F-22 — VPN status · **S**
`SCDynamicStore` on `State:/Network/Global/IPv4` plus `NEVPNManager` status, with a `utun`/`ppp` interface heuristic as fallback. Sticky live activity with connected duration. Show the interface name; don't guess the provider.

### F-23 — Low Power Mode toggle · **S**
Read via `ProcessInfo.processInfo.isLowPowerModeEnabled`; setting it needs privileged `pmset`, so route through the helper's `power` capability. Wire into the existing battery activity as a one-tap action at low-battery thresholds, and add a `FunctionButtonAction` case.

### F-24 — Meeting controls · **M**
Detect an active meeting from mic-in-use (`kAudioDevicePropertyDeviceIsRunningSomewhere`) plus a running-app check for Zoom / Teams / Meet. Mute and leave via per-app shortcuts posted through the helper's `input` capability (Zoom ⇧⌘A, Meet ⌘D in Chrome, Teams ⇧⌘M). `FunctionButtonAction.toggleMicrophone` already exists — build on it. Even without app control, a reliable "your mic is live" indicator is worth shipping alone.

### F-25 — AI agent progress · **M**

Droppy shows Claude Code / Codex / Cursor state in the notch. Clean implementation, no scraping:

- Run a local listener: Unix socket at `~/Library/Application Support/BoringNotch/agent.sock` (⚠ verify reachability from an arbitrary shell process given the sandbox container path; fall back to `127.0.0.1` on a port written to a well-known file).
- Ship an install script registering Claude Code hooks (`PreToolUse`, `PostToolUse`, `Stop`, `Notification`) that POST `{agent, session, state, tool, elapsed}`.
- For agents without hooks, watch their session log directory via `DispatchSource` file-system events.
- Render as a live activity: agent icon, state (thinking / running tool / waiting / done), elapsed, tap to focus the owning terminal window.

**Acceptance:** a running session updates within 1 s of a hook firing; a killed agent clears within 30 s via heartbeat timeout.

### F-31 — Notification inline reply · **L** · ⚠ risky

You already solved the hard half — `NotificationWatcher` reads the AX tree and tracks `isUnsupportedLayout`. Reply means finding the banner's reply affordance in that same tree, expanding it, setting `kAXValueAttribute` on the text field, and pressing Send — all from the helper under `axNotifications`.

Spike it against Messages on the current macOS first and report which AX roles appear. If the tree doesn't expose the field reliably, fall back to app-specific paths (Messages via AppleScript, already entitled) and don't advertise general reply. Off by default; never log message bodies.

---

## 7. Phase 3 — Power tools (helper-dependent; F-01 must be merged)

### F-30 — Window snapping · **L**
Helper enumerates windows via `AXUIElementCreateApplication` + `kAXWindowsAttribute` and sets `kAXPositionAttribute` / `kAXSizeAttribute`. App side: a global mouse monitor for drag-to-edge zones with a translucent preview, plus `KeyboardShortcuts` bindings for halves / quarters / thirds / maximise / centre / restore. Per-display; skip full-screen spaces and Stage Manager windows. Keep a small undo stack of prior frames.

### F-32 — Keystroke sounds · **M**
A listen-only `CGEventTap` in the helper (keyDown/keyUp only, **never** persisting key codes) → app plays samples through a preloaded `AVAudioEngine` sampler with per-key pitch variation. Ship 3–4 royalty-free switch profiles with licences recorded in `THIRD_PARTY_LICENSES`; allow user sample folders.
Enabling this must show an explicit disclosure: *this observes every keystroke locally to play a sound; nothing is stored or transmitted.* Anything less is indefensible for a DMG-distributed app.

### F-33 — Console (terminal in the notch) · **L** · highest risk in this plan
Helper spawns a PTY (`forkpty` + `login -fp $USER`) and streams bytes over XPC; the app renders with **SwiftTerm** (SPM, MIT). Ephemeral sessions, capped scrollback, no persistence in v1.
A shell spawned by an unsandboxed helper and reachable from a hover target is the largest attack surface here. **Do not start before F-01 ships.** Default off, explicit opt-in with a plain-language warning.

---

## 8. Phase 4 — Creation tools

### F-40 — Voice recorder + transcription · **L**
`AudioCaptureManager` already handles capture plumbing for the waveform — extend it rather than duplicating. Record to `.m4a` in Application Support, waveform while recording, transcription via `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`; feature-detect `SpeechAnalyzer` / `SpeechTranscriber` on macOS 26 and prefer it when present. Transcript stored alongside and searchable. Audio never leaves the machine.

### F-41 — Background removal · **S** · best effort-to-impact ratio here
`VNGenerateForegroundInstanceMaskRequest` (Vision, macOS 14+) as a shelf item action: right-click an image → Remove Background → new shelf item as PNG with alpha. Fully on-device, no model to ship, ~150 lines.

### F-42 — File conversion · **M**
Images via ImageIO / CoreImage (HEIC/PNG/JPEG/TIFF, quality, resize); audio and video via `AVAssetExportSession` presets. **Do not bundle ffmpeg** — licence plus sandbox-exec problems. Optionally detect a Homebrew ffmpeg and offer to use *their* install through the helper, clearly labelled.

### F-43 — Motion art · **M**
A board widget rendering a bundled Metal shader, a user Lottie file (`customVisualizers` already models this), or a looping video via `AVPlayerLooper`. Hard-pause rendering when the notch is closed or the display sleeps — this is the easiest place in the app to accidentally burn 15% CPU.

---

## 9. Phase 5 — Long tail

### F-14 — Universal launcher · **L**
`AppSwitcherManager` covers running apps. A launcher adds `NSMetadataQuery` for installed apps and files plus in-app actions (open a shelf item, start a timer, paste a clipboard entry, run a `FunctionButtonAction`) in one frecency-ranked list behind a global hotkey. Scope guard: apps + files + in-app actions. This is not Raycast.

### F-15 — Emoji picker · **M**
Bundled CLDR annotation data (record the licence), categories, keyword search, skin tones, frecency recents. Copies to the pasteboard; optional auto-paste via the helper's `input` capability.

### F-50 — Natural-language calendar entry · **M**
`NSDataDetector(.date)` plus a small rules layer for "tomorrow 3pm", "every Tuesday", "in 20 min", "for 45m", and `@calendar` / `#list` tokens. Parsed preview before commit, EventKit to write. Degrade to a date picker when parsing fails — and remember Crowdin means this ships in many locales.

### F-51 — Share links · **L**
Droppy Cloud is hosted infrastructure; a free open-source app shouldn't run one on your dime. Extend the existing `QuickShareService` / `ShareServiceFinder` seam with pluggable backends:
1. **Local / LAN** (default, no account): a short-lived local HTTP endpoint plus QR code, using the `network.server` entitlement you already have.
2. **Bring your own storage:** S3-compatible (R2/B2/MinIO), WebDAV, or SCP. Credentials in Keychain.
3. **Hosted:** only if you ever want to run one — separate opt-in, never the default.

### F-52 — Third-party add-ons · **XL**
`ExtensionAPI.swift`'s header comment already states the position correctly: in-process registration is deliberate, and this API is the layer a future out-of-process host sits behind. Real third-party code needs a signed bundle format, a capability manifest, an XPC sandbox per add-on, and a review story. Write an ADR before any code, and only if people actually ask.

---

## 10. Cross-cutting

**Privacy.** You now capture clipboard, read the notification AX tree, sample audio, and (with F-32) observe keystrokes. Requirements: every such feature off by default with an explicit disclosure at enable time; per-app exclusion lists (clipboard has one — mirror it for notifications and keyclick); retention limits; a Privacy pane with per-store size and a single wipe button; nothing leaves the machine except user-initiated shares and disclosed lookups (weather, lyrics), both disableable.

**Performance.** Budget: ≤1% idle CPU with defaults, ≤3% with everything on. No polling faster than 1 Hz except clipboard change detection (~0.4 s) and active animations. Every extension's `deactivate()` must actually stop its timers, taps, and observers — with 9 built-ins today and 19 features planned, verify in Instruments per feature, not at the end.

**Testing.** There are none. Start with the cheap ones that catch real bugs: `NotchLayoutResolver.reconcile`, LRC parsing, clipboard dedupe/exclusion, shake detection (replay recorded traces), timer drift across simulated sleep, board layout migration. Everything else stays a documented manual matrix per phase (notched MBP, external display, both, lock screen, macOS 14/15/26).

**Localisation.** `Localizable.xcstrings` grew 3,600 lines in one commit — the discipline is already there. Keep it: no hardcoded English in new views.

**Settings.** The `Settings/Views/*` per-feature split is good. Keep new panes there and out of `SettingsView.swift`.

---

## 11. Suggested execution order

| Sprint | Content | Ships as |
| --- | --- | --- |
| 1 | F-01, F-02 | (internal — unblocks everything privileged) |
| 2 | F-04, F-03 | "Works on every display" |
| 3 | F-10, F-12, F-13 | "Catcher, screenshot editor, Pomodoro" |
| 4 | F-11 | "Design your own layout" |
| 5 | F-20, F-21 | "Queue and audio output" |
| 6 | F-22, F-23, F-24, F-25 | "VPN, Low Power, meetings, agent progress" |
| 7 | F-41, F-42, F-15 | "Background removal, conversion, emoji" |
| 8 | F-30 | "Window management" |
| 9 | F-40, F-32, F-43 | "Voice notes, keyclick, motion art" |
| 10 | F-14, F-50 | "Launcher, natural-language entry" |
| 11 | F-31 spike → ship or descope | "Notification reply" (conditional) |
| 12 | F-33, F-51, F-52 | "Console, share links, add-on SDK" |

Only Sprint 1 has no user-visible payoff.

---

## 12. Open decisions

1. **XPC hardening (F-01)** — confirm it lands before any of F-15/24/30/32/33. This is the one item where shipping order is a security question, not a preference.
2. **GRDB** — accept a new SPM dependency for clipboard / notification / recording history, or keep ad-hoc persistence? Recommend deciding before F-40 adds transcripts.
3. **Activity bus (F-03)** — refactor now, or keep adding claimants to `sneakPeek` / `expandingView`? Recommend now; the cost only grows.
4. **Console (F-33)** — ship at all? Largest attack surface, and the feature Droppy users mention least.
5. **Notification reply (F-31)** — commit to the spike or descope. Deciding early avoids a wasted L.
6. **Share links (F-51)** — local/LAN + BYO storage only, or is hosted on the table?
7. **Minimum macOS** — staying at 14.0 costs availability checks for Speech and ScreenCaptureKit. Raising to 15 simplifies F-12 and F-40 and drops users.
8. **Signing** — the README still says there's no Apple Developer account and gives `xattr -dr` as the install step. F-01's client validation is weaker without a stable signing identity, and Sparkle updates plus TCC grants are all worse unsigned. Worth revisiting given how much privileged surface this plan adds.

---

## 13. Prompt templates for Claude Code

**Starting a phase:**
> Read `DROPPY_PARITY_PLAN.md` §4 and `CLAUDE.md`. Implement F-01 only. Before writing code, produce a design note covering how you'll validate the client's code signature, how capability gating maps to user settings, and exactly which files you'll touch. Do not start F-02.

**Starting a feature:**
> Implement F-10 per §5. Register it through `ExtensionRegistry` following the pattern in `ExtensionSystem/BuiltInExtensions.swift`. Structure new code the way `components/Shelf/` is structured. Declare `Defaults` keys in the feature's own file, not `models/Constants.swift`. When done, list the acceptance criteria and how you verified each.

**Spikes:**
> Spike only, throwaway branch: prove that the reply affordance of a Messages notification banner is reachable and settable through the AX tree on this macOS version, from inside `BoringNotchXPCHelper`. Report the AX roles you found. Max 150 lines. Do not integrate.

**Guardrail worth repeating:**
> This is a fork tracking an active upstream, and `dev` already carries a large delta. Prefer new files. If you must edit an existing upstream file, make the smallest possible change and log it in `FORK_NOTES.md`.
