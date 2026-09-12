//
//  FloatingNotchDefaults.swift
//  boringNotch
//
//  F-04: position and width settings for the floating pill shown on a
//  notchless (external) display, where there is no physical bezel to anchor
//  against and so nothing to pin the pill's placement or size for us.
//

import Defaults
import Foundation
import CoreGraphics

extension Defaults.Keys {
    /// Width of the closed pill on a notchless display, replacing the
    /// hardcoded 185pt fallback `getClosedNotchSize` uses when there is no
    /// physical notch to measure.
    static let floatingNotchWidth = Key<CGFloat>("floatingNotchWidth", default: 185)

    /// Horizontal offset from top-center of a notchless display, in points.
    /// Positive moves the pill right.
    static let floatingNotchHorizontalOffset = Key<CGFloat>("floatingNotchHorizontalOffset", default: 0)

    /// Gap between the top of a notchless display and the top of the pill.
    static let floatingNotchTopGap = Key<CGFloat>("floatingNotchTopGap", default: 8)
}
