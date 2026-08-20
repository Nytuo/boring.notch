//
//  Constants.swift
//  boringNotch
//
//  Created by Richard Kunkli on 16/08/2024.
//

import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let clipboardHistoryPanel = Self("clipboardHistoryPanel", default: .init(.c, modifiers: [.shift, .command]))
    static let toggleMicrophone = Self("toggleMicrophone", default: .init(.f5, modifiers: [.function]))
    static let decreaseBacklight = Self("decreaseBacklight", default: .init(.f1, modifiers: [.command]))
    static let increaseBacklight = Self("increaseBacklight", default: .init(.f2, modifiers: [.command]))
    static let toggleSneakPeek = Self("toggleSneakPeek", default: .init(.h, modifiers: [.command, .shift]))
    static let toggleNotchOpen = Self("toggleNotchOpen", default: .init(.i, modifiers: [.command, .shift]))
    static let toggleCaffeine = Self("toggleCaffeine", default: .init(.k, modifiers: [.command, .shift]))
    static let toggleAppSwitcher = Self("toggleAppSwitcher", default: .init(.a, modifiers: [.command, .shift]))

    // F-30: window snapping. Only the two most common actions ship with a
    // default binding; the rest are opt-in from Settings > Shortcuts so
    // enabling the feature doesn't silently claim eight more global hotkeys.
    static let snapWindowLeftHalf = Self("snapWindowLeftHalf", default: .init(.leftBracket, modifiers: [.control, .option, .command]))
    static let snapWindowRightHalf = Self("snapWindowRightHalf", default: .init(.rightBracket, modifiers: [.control, .option, .command]))
    static let snapWindowTopHalf = Self("snapWindowTopHalf")
    static let snapWindowBottomHalf = Self("snapWindowBottomHalf")
    static let snapWindowTopLeftQuarter = Self("snapWindowTopLeftQuarter")
    static let snapWindowTopRightQuarter = Self("snapWindowTopRightQuarter")
    static let snapWindowBottomLeftQuarter = Self("snapWindowBottomLeftQuarter")
    static let snapWindowBottomRightQuarter = Self("snapWindowBottomRightQuarter")
    static let snapWindowMaximize = Self("snapWindowMaximize", default: .init(.return, modifiers: [.control, .option, .command]))
    static let snapWindowCenter = Self("snapWindowCenter")
    static let snapWindowRestore = Self("snapWindowRestore", default: .init(.delete, modifiers: [.control, .option, .command]))

    // F-14
    static let toggleLauncher = Self("toggleLauncher", default: .init(.space, modifiers: [.option, .command]))
}
