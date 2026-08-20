//
//  XPCHelperCapabilities.swift
//  boringNotch
//
//  F-01: user-facing settings for the privileged capability groups the XPC
//  helper gates. None of the features that need these exist yet
//  (F-30/F-31/F-15/F-24/F-33/F-23); the toggles are declared now so the
//  gating plumbing (XPCHelperClient.pushCapabilities, HelperCapabilityGate on
//  the helper side) exists before any privileged feature lands.
//
//  Declared in their own file per CLAUDE.md — `models/Constants.swift` does
//  not grow for new features.
//

import Defaults

extension Defaults.Keys {
    /// Window enumeration/positioning via the Accessibility API (F-30).
    static let capabilityAxWindowsEnabled = Key<Bool>("capabilityAxWindowsEnabled", default: false)
    /// Invoking a notification's reply/action affordance via the Accessibility API (F-31).
    static let capabilityAxNotificationsEnabled = Key<Bool>("capabilityAxNotificationsEnabled", default: false)
    /// Posting synthetic keystrokes / running an event tap (F-15, F-24, F-32).
    static let capabilityInputEnabled = Key<Bool>("capabilityInputEnabled", default: false)
    /// Spawning and driving a PTY (F-33).
    static let capabilityPtyEnabled = Key<Bool>("capabilityPtyEnabled", default: false)
    /// Toggling Low Power Mode via `pmset` (F-23).
    static let capabilityPowerEnabled = Key<Bool>("capabilityPowerEnabled", default: false)
}

enum HelperCapabilitySettings {
    /// All capability toggles, keyed by their `HelperCapability` raw value on
    /// the helper side, ready to push over `updateCapabilities(_:with:)`.
    static var current: [String: Bool] {
        [
            "axWindows": Defaults[.capabilityAxWindowsEnabled],
            "axNotifications": Defaults[.capabilityAxNotificationsEnabled],
            "input": Defaults[.capabilityInputEnabled],
            "pty": Defaults[.capabilityPtyEnabled],
            "power": Defaults[.capabilityPowerEnabled],
        ]
    }
}
