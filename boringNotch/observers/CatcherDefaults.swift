//
//  CatcherDefaults.swift
//  boringNotch
//
//  F-10 settings, in their own file per CLAUDE.md.
//

import Defaults

extension Defaults.Keys {
    static let catcherEnabled = Key<Bool>("catcherEnabled", default: true)
    /// Multiplier on the base 40pt reversal-amplitude threshold — higher is
    /// more sensitive (triggers on smaller shakes).
    static let catcherSensitivity = Key<Double>("catcherSensitivity", default: 1.0)
    static let catcherAutoCloseDelay = Key<Double>("catcherAutoCloseDelay", default: 2.0)
}
