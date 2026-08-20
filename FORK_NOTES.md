# FORK_NOTES.md

Every edit to an upstream (`TheBoredTeam/boring.notch`) file, logged per `CLAUDE.md` fork discipline. Files created entirely within this fork (e.g. everything under `BoringNotchXPCHelper/`, `ExtensionSystem/`) are not upstream and are not logged here.

| File | Reason |
| --- | --- |
| `boringNotch/Localizable.xcstrings` | F-01/F-02/F-13/F-10/F-12/F-11: additive-only string key insertions for each feature's UI. No existing keys changed. |
| `boringNotch/ContentView.swift` | F-04: `currentNotchShape` picks `IslandShape` vs `NotchShape` on `vm.hasNotch`, notched branch unchanged. F-11: one `case .board: BoardView()` added to the tab-content switch. F-40: one more `else if` branch in `computedChinWidth` and the banner switch for the voice-recording live activity, same shape as the others. F-14: one `case .launcher: LauncherView()` added to the tab-content switch. |
| `boringNotch/Info.plist` | F-40: added `NSMicrophoneUsageDescription`/`NSSpeechRecognitionUsageDescription` for voice notes — first feature needing either. Additive only. |
| `boringNotch/enums/generic.swift` | F-11: `.board` case added to `NotchViews` (`openSize`/`hugsContent`), same shape as every other case. F-14: `.launcher` added the same way. |
| `boringNotch/boringNotchApp.swift` | F-10: `CatcherPresenter` wired into `setupDragDetectorForScreen`'s existing `DragDetector` instances (`onDragMove`/`onDragEnd`), plus a small `autoCloseShelfIfShowing` helper. F-30: a keyboard-shortcut-to-zone loop added next to the existing `KeyboardShortcuts.onKeyDown` calls, same shape. F-32: one line touching `KeystrokeSoundManager.shared` so its Combine subscriptions start at launch, matching the other managers touched there. F-14: one more `KeyboardShortcuts.onKeyDown` block, same shape as the others. |
| `boringNotch/components/Settings/Views/SettingsView.swift` | F-11: one `case .board` added to the settings sidebar enum/switch, same shape as every other tab. F-32: one `case .keystrokeSounds` added the same way. F-14: one `case .launcher` added the same way. |
| `boringNotch/BoringViewCoordinator.swift` | F-20/F-22/F-24/F-25: `.vpn`/`.meeting`/`.agentProgress` cases added to `SneakContentType`, same shape as the existing cases. F-40: `.voiceRecording` added the same way. |
| `boringNotch/components/Notch/BoringHeader.swift` | F-22: one `case .vpn: VPNHeaderIndicator()` added to `headerAccessory(_:)`, same shape as every other case. |
| `boringNotch/components/Settings/Views/AdvancedSettingsView.swift` | F-23/F-30: "Privileged features" `Section` (toggles for the XPC helper's `power` and `axWindows` capabilities), appended before the existing `Form`'s closing brace — no existing content touched. |
| `boringNotch/Shortcuts/ShortcutConstants.swift` | F-30: 11 new `KeyboardShortcuts.Name` entries for window snapping, same shape as the existing ones. F-14: one more (`toggleLauncher`), same shape. |
| `boringNotch/components/Settings/Views/ShortcutsSettingsView.swift` | F-30: one new "Window Snapping" `Section` of `KeyboardShortcuts.Recorder`s, appended after the existing sections. F-14: one more `Section` with a single recorder, same shape. |
| `boringNotch.xcodeproj/project.pbxproj` | F-50: reworded `INFOPLIST_KEY_NSCalendarsUsageDescription` (Debug + Release) to mention creating events, not just displaying them — the existing string undersold what full calendar access grants once writes are added. |
