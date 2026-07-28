//
//  CaffeineMenuSection.swift
//  boringNotch
//

import Defaults
import SwiftUI

/// Keep Awake controls, rendered inside a `MenuBarExtra`.
///
/// Must stay a flat list of menu primitives — containers other than
/// `Divider`/`Menu` do not survive the SwiftUI-to-NSMenu translation.
struct CaffeineMenuSection: View {
    @ObservedObject private var caffeine = CaffeineManager.shared

    /// Whether to draw the leading `Divider`. Set when these controls are
    /// appended to the main menu; the standalone Keep Awake menu does not want
    /// a separator above its first item.
    var showsDivider: Bool = true

    var body: some View {
        if showsDivider {
            Divider()
        }

        if caffeine.isActive {
            Button(stopTitle) {
                caffeine.deactivate()
            }
            if caffeine.expiresAt != nil {
                Button("Add 15 Minutes") {
                    caffeine.extend(by: 15 * 60)
                }
            }
            Divider()
            Menu("Restart For") {
                durationButtons
            }
        } else {
            Menu("Keep Awake") {
                durationButtons
            }
        }
    }

    @ViewBuilder
    private var durationButtons: some View {
        ForEach(CaffeineDuration.presets) { preset in
            Button(preset.localizedString) {
                caffeine.activate(for: preset)
            }
        }
    }

    private var stopTitle: String {
        if let remaining = caffeine.formattedRemaining {
            return String(
                format: NSLocalizedString(
                    "caffeine_menu_stop_with_time",
                    comment: "Menu item to stop Keep Awake, showing remaining time"
                ),
                remaining
            )
        }
        return NSLocalizedString(
            "caffeine_menu_stop",
            comment: "Menu item to stop Keep Awake"
        )
    }
}
