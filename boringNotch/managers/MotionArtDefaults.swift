//
//  MotionArtDefaults.swift
//  boringNotch
//

import Defaults
import Foundation

extension Defaults.Keys {
    static let motionArtEnabled = Key<Bool>("motionArtEnabled", default: false)
    static let motionArtVideoBookmark = Key<Data?>("motionArtVideoBookmark", default: nil)
}
