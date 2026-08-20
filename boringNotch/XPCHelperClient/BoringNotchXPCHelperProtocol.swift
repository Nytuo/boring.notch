//
//  BoringNotchXPCHelperProtocol.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation

/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
/// `NSXPCConnection` supports exactly one `exportedObject`/
/// `remoteObjectInterface` pair per connection — this is that one callback
/// channel, shared by everything the helper needs to push to the app rather
/// than reply to. Lunar owns it today; F-32's keystroke pitch-bucket
/// callback (`keystrokeDidOccur`) rides the same channel — see
/// `XPCHelperClient.CombinedHelperListener` for how the two stay independent
/// despite sharing one exported object.
@objc protocol BoringNotchXPCHelperLunarListener {
    func lunarEventDidUpdate(_ event: BNLunarBrightnessEvent)
    func lunarStreamDidStop(_ reason: String?)
    /// F-32: fired once per key-down while the observer is running. Carries
    /// only a coarse 0-11 bucket derived from the key code inside the
    /// helper's event-tap callback — never the key code itself, never
    /// anything that could reconstruct what was typed. `@objc optional` so
    /// `LunarEventListener` (which only cares about the Lunar methods)
    /// doesn't need a no-op implementation.
    @objc optional func keystrokeDidOccur(_ pitchIndex: Int32)
}

@objc(BNLunarBrightnessEvent)
final class BNLunarBrightnessEvent: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    let brightness: Double
    let display: Int

    init(brightness: Double, display: Int) {
        self.brightness = brightness
        self.display = display
        super.init()
    }

    required init?(coder: NSCoder) {
        brightness = coder.decodeDouble(forKey: "brightness")
        display = coder.decodeInteger(forKey: "display")
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(brightness, forKey: "brightness")
        coder.encode(display, forKey: "display")
    }
}

@objc protocol BoringNotchXPCHelperProtocol {
    func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void)
    func requestAccessibilityAuthorization()
    func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void)
    // Keyboard backlight / CoreBrightness access (performed by the helper)
    func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Screen brightness access (performed by the helper)
    func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    // returns the displayID that will be used for built-in brightness operations (main or internal fallback)
    func displayIDForBrightness(with reply: @escaping (NSNumber?) -> Void)
    func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    func adjustScreenBrightness(by value: Float, with reply: @escaping (Bool) -> Void)
    // Lunar brightness events (performed by the helper)
    func isLunarAvailable(with reply: @escaping (Bool) -> Void)
    func startLunarEventStream(with reply: @escaping (Bool) -> Void)
    func stopLunarEventStream()
    /// Write Lunar's hideOSD preference (disable/enable Lunar's OSD when we replace it).
    func setLunarOSDHidden(_ hide: Bool, with reply: @escaping (Bool) -> Void)
    /// Pushes the app's current capability toggles (F-01). Keys are
    /// `HelperCapability` raw values; the helper re-checks these before any
    /// future privileged call (window control, keystroke posting, PTY, etc.)
    /// and refuses when the corresponding setting is off.
    func updateCapabilities(_ settings: [String: Bool], with reply: @escaping (Bool) -> Void)
    /// F-23: toggles Low Power Mode via `pmset`. Gated on the `power`
    /// capability — refuses (replies `false`) when it's off.
    func setLowPowerMode(_ enabled: Bool, with reply: @escaping (Bool) -> Void)
    /// F-30: moves/resizes the frontmost app's focused window to
    /// `(x, y, width, height)` in Quartz (top-left-origin) global display
    /// coordinates. Gated on the `axWindows` capability. Reads the window's
    /// frame before changing it and replies with both the outcome and that
    /// prior frame in one round trip — the prior frame is what a "restore"
    /// action re-sends, so there's no separate get/set race to get wrong.
    /// Refuses (all-false/zero reply) when the capability is off, when
    /// Accessibility isn't authorized, or when the focused window is
    /// full-screen (`AXFullScreen` true) — repositioning a full-screen-space
    /// window isn't meaningful.
    func setFocusedWindowFrame(
        _ x: Double, _ y: Double, _ width: Double, _ height: Double,
        with reply: @escaping (Bool, Double, Double, Double, Double) -> Void
    )
    /// F-32: starts a listen-only key-down observer, gated on the `input`
    /// capability. Each key-down fires `keystrokeDidOccur` on the connection's
    /// listener with a coarse pitch bucket only — see that method's doc
    /// comment. Refuses (replies `false`) when the capability is off.
    func startKeystrokeObserver(with reply: @escaping (Bool) -> Void)
    /// Stops the observer started by `startKeystrokeObserver`. Safe to call
    /// even if it was never started.
    func stopKeystrokeObserver()
    /// Bundle identifiers to skip: the observer checks the frontmost app
    /// against this set on every key-down and drops the callback entirely
    /// for a match, before any bucket is computed. CLAUDE.md requires a
    /// per-app exclusion list for keystroke observation — this is it.
    func setKeystrokeExcludedApps(_ bundleIDs: [String])
}
