# CLAUDE.md — working rules for this repository

Fork of `TheBoredTeam/boring.notch`: a SwiftUI macOS app that turns the MacBook notch into a productivity surface. **Active branch is `dev`**, which carries a large fork-specific delta on top of upstream.

The work programme is in `DROPPY_PARITY_PLAN.md`. Read it before implementing anything with an `F-xx` identifier.

---

## Project facts

- **Language/UI:** Swift 5.9+, SwiftUI with AppKit interop. `@MainActor` on view-adjacent types.
- **Minimum OS:** macOS 14 (Sonoma). Build with Xcode 26 on macOS 15.6+.
- **Build:** `boringNotch.xcodeproj`. No workspace, no CocoaPods. SPM deps pinned in the project file.
- **Targets:** `boringNotch` (sandboxed app), `BoringNotchXPCHelper` (**not** sandboxed), `updater`.
- **Deps:** Defaults, KeyboardShortcuts, LaunchAtLogin-Modern, Sparkle, Lottie, Pow, SkyLightWindow, MacroVisionKit, AsyncXPCConnection, swift-collections, swiftui-introspect.

---

## Architecture — use what's already there

- **Features are extensions.** `ExtensionSystem/ExtensionAPI.swift` defines `BoringExtension` (manifest, capabilities, `activate()`/`deactivate()`, optional settings view and tab). Register in `BuiltInExtensions.swift` → `ExtensionRegistry.registerBuiltInExtensions()`. Do not invent a parallel plugin concept.
- **`isEnabled` proxies the feature's own `Defaults` key.** That's deliberate, so the extensions gallery and the feature's settings pane can never disagree. Keep it.
- **Notch destinations** are `NotchTabItem` → `NotchViews`, ordered through `models/NotchLayout.swift`. New tabs must: add a case to both enums, set `openSize` and `hugsContent`, and define `isEnabled`. `NotchLayoutResolver.reconcile` handles migrating stored order — you get that for free.
- **A header icon suppresses its duplicate tab** (`headerCounterpart` / `isShadowedByHeaderItem`). Respect this for anything that wants both surfaces.
- **State lives in the feature's manager** (`managers/*Manager.swift`, `ObservableObject`, explicit `start()`/`stop()`), not in `BoringViewCoordinator` or `ContentView`.
- **Settings panes** go in `components/Settings/Views/`, one file per feature. Don't grow `SettingsView.swift`.
- **Privileged work** goes through `BoringNotchXPCHelper` over XPC. The app is sandboxed; never add entitlements to dodge that.

Structural model to imitate for anything non-trivial: `components/Shelf/` (`Models/`, `Services/`, `ViewModels/`, `Views/`).

---

## Fork discipline

Upstream is active and `main` gets merged into `dev` periodically. Every edit to an upstream file is future conflict surface, and there's already a lot of it.

1. **Add new files rather than editing existing ones.**
2. When an upstream file must change, make it a **single registration or delegation call**, not inline logic.
3. Log every touched upstream file in `FORK_NOTES.md`: path, reason, one line.
4. Never reformat or "tidy" an upstream file you're passing through.

---

## Conventions

- **`Defaults` keys:** declare new ones in the feature's own file. `models/Constants.swift` is already ~160 keys and should not grow.
- **Enum raw values are persisted.** Renaming a `NotchTabItem` / `NotchHeaderItem` / `LockScreenWidget` case breaks stored user layouts — add a mapping in `init?(rawValue:)` the way `player`/`home` does.
- **Strings:** `NSLocalizedString` with a stable key, into `Localizable.xcstrings`. Crowdin syncs from `crowdin.yml`. No hardcoded English in views.
- **Concurrency:** `async/await` in new code. `@MainActor` for anything touching views. No semaphores on the main thread.
- **Logging:** `utils/Logger.swift`. Never log clipboard contents, notification bodies, keystrokes, file contents, or transcripts — not at any level.
- **Errors:** surface permission failures in the UI with the reason and a deep link to the right System Settings pane. `NotificationWatcher.needsAccessibility` and `ScreenshotManager.needsFolderAccess` are the pattern to follow. Never fail silently on denial.

---

## Performance rules

- ≤1% idle CPU with default features, ≤3% with everything enabled.
- No polling faster than 1 Hz except clipboard change detection (~0.4 s) and active animations.
- `deactivate()` must genuinely stop every timer, observer, event tap, and render loop the feature started. Verify in Instruments.
- Views must not re-render on unrelated `Defaults` changes.

---

## Privacy rules (non-negotiable)

- Honour `org.nspasteboard.ConcealedType` and `org.nspasteboard.TransientType`.
- Anything observing user content (clipboard, notifications, audio, keystrokes) is **off by default** and shows an explicit disclosure at enable time, before the TCC prompt.
- Per-app exclusion lists for clipboard, notifications, and keystroke observation.
- History is local, retention-limited, and wipeable from one button.
- Nothing leaves the machine except user-initiated shares and disclosed lookups (weather, lyrics), both disableable.

---

## Security rules for the XPC helper

The helper is **unsandboxed**, and `shouldAcceptNewConnection` currently accepts any client. Treat every addition as a security review.

- Validate the peer's code signature and team identifier before accepting the connection (F-01). Nothing that posts keystrokes, spawns a shell, or moves other apps' windows ships before that lands.
- Each capability (`axWindows`, `axNotifications`, `input`, `pty`, `capture`, `power`) is individually gated and refuses when its user setting is off.
- Never accept a shell command, path, or arbitrary key sequence from outside validated app code. No pass-through `exec`.
- Log every privileged call — operation name only, never arguments containing user content.

---

## Definition of done

1. Every acceptance criterion in the plan section is met, and you've stated how you verified each.
2. Builds clean, no new warnings.
3. `deactivate()` leaves no residual timers, taps, or observers (verified in Instruments).
4. All strings localised.
5. Permissions declared on the manifest, requested at enable time, denial handled gracefully.
6. New/changed `Defaults` shapes have migration handling.
7. `FORK_NOTES.md` updated if an upstream file was touched.
8. A `WhatsNewView` entry if user-visible.

---

## Things not to do

- Don't inspect, decompile, or copy from Droppy or any other closed-source notch app. Feature ideas only.
- Don't reuse Droppy's names: Droplet, Basket, TermiNotch, Mechey, Droppy Cloud, The Trench.
- Don't de-sandbox the main app.
- Don't bundle ffmpeg or other GPL/LGPL binaries.
- Don't add WeatherKit, CloudKit, or anything needing a paid Apple Developer account.
- Don't add `Defaults.Keys` to `models/Constants.swift`.
- Don't add per-feature state to `BoringViewCoordinator` or `ContentView`.
- Don't claim a capability the platform doesn't support (syncing with Clock.app timers, enumerating AirPlay targets). Ship the honest analogue and say what it is.
