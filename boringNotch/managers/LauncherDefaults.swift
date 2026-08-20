//
//  LauncherDefaults.swift
//  boringNotch
//

import Defaults

extension Defaults.Keys {
    static let launcherEnabled = Key<Bool>("launcherEnabled", default: false)
    /// Bundle identifiers, most-recently-used first, capped at 20.
    static let launcherRecentApps = Key<[String]>("launcherRecentApps", default: [])
}
