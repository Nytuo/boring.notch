//
//  KeystrokeSoundDefaults.swift
//  boringNotch
//

import Defaults

extension Defaults.Keys {
    static let keystrokeSoundsEnabled = Key<Bool>("keystrokeSoundsEnabled", default: false)
    static let keystrokeSoundsVolume = Key<Double>("keystrokeSoundsVolume", default: 0.5)
    /// Bundle identifiers the observer skips entirely — same convention as
    /// `clipboardExcludedApps`/`notificationsExcludedApps`.
    static let keystrokeSoundsExcludedApps = Key<[String]>("keystrokeSoundsExcludedApps", default: [])
}
