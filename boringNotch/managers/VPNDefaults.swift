//
//  VPNDefaults.swift
//  boringNotch
//

import Defaults

extension Defaults.Keys {
    static let vpnStatusEnabled = Key<Bool>("vpnStatusEnabled", default: false)
    static let vpnStatusLiveActivity = Key<Bool>("vpnStatusLiveActivity", default: true)
    static let vpnStatusHeaderIcon = Key<Bool>("vpnStatusHeaderIcon", default: false)
}
