//
//  NotchLayout.swift
//  boringNotch
//
//  User-orderable notch content: header accessories and tabs.
//

import Defaults
import SwiftUI

// MARK: - Header accessories

/// An item that can appear in the trailing area of the opened notch header.
///
/// The stored order is the render order, left to right. Items whose feature is
/// switched off are skipped at render time rather than removed from the list,
/// so a user's arrangement survives toggling a feature off and on again.
enum NotchHeaderItem: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case mirror
    case weather
    case caffeine
    case bluetooth
    case systemStats
    case battery

    var id: String { rawValue }

    static let defaultOrder: [NotchHeaderItem] = [
        .mirror,
        .weather,
        .caffeine,
        .bluetooth,
        .systemStats,
        .battery
    ]

    var label: String {
        switch self {
        case .mirror:
            return NSLocalizedString("layout_item_mirror", comment: "Notch header item: camera mirror")
        case .weather:
            return NSLocalizedString("layout_item_weather", comment: "Notch header item: weather")
        case .caffeine:
            return NSLocalizedString("layout_item_caffeine", comment: "Notch header item: keep awake")
        case .bluetooth:
            return NSLocalizedString("layout_item_bluetooth", comment: "Notch header item: bluetooth devices")
        case .systemStats:
            return NSLocalizedString("layout_item_stats", comment: "Notch header item: system stats")
        case .battery:
            return NSLocalizedString("layout_item_battery", comment: "Notch header item: battery")
        }
    }

    var iconName: String {
        switch self {
        case .mirror: return "web.camera"
        case .weather: return "cloud.sun.fill"
        case .caffeine: return "cup.and.saucer.fill"
        case .bluetooth: return "wave.3.right.circle"
        case .systemStats: return "chart.line.uptrend.xyaxis"
        case .battery: return "battery.100"
        }
    }

    /// The preference that governs whether this item is shown at all.
    /// Reordering cannot make a disabled feature appear.
    @MainActor
    var isEnabled: Bool {
        switch self {
        case .mirror: return Defaults[.showMirror]
        case .weather: return Defaults[.weatherEnabled] && Defaults[.weatherShowInNotch]
        case .caffeine: return Defaults[.caffeineEnabled] && Defaults[.caffeineNotchIcon]
        case .bluetooth: return Defaults[.bluetoothNotchIcon]
        case .systemStats: return Defaults[.systemStatsEnabled] && Defaults[.systemStatsNotchIcon]
        case .battery: return Defaults[.showBatteryIndicator]
        }
    }

    /// Name of the setting that controls this item, for the layout pane's hint.
    var controllingSettingName: String {
        switch self {
        case .mirror:
            return NSLocalizedString("layout_setting_mirror", comment: "Setting that enables the mirror item")
        case .weather:
            return NSLocalizedString("layout_setting_weather", comment: "Setting that enables the weather item")
        case .caffeine:
            return NSLocalizedString("layout_setting_caffeine", comment: "Setting that enables the keep awake item")
        case .bluetooth:
            return NSLocalizedString("layout_setting_bluetooth", comment: "Setting that enables the bluetooth item")
        case .systemStats:
            return NSLocalizedString("layout_setting_stats", comment: "Setting that enables the system stats item")
        case .battery:
            return NSLocalizedString("layout_setting_battery", comment: "Setting that enables the battery item")
        }
    }
}

// MARK: - Tabs

/// A destination in the opened notch's tab strip.
enum NotchTabItem: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case player
    case shelf
    case calendar
    case weather
    case clipboard
    case apps
    case clock
    case systemStats
    case bluetooth

    var id: String { rawValue }

    static let defaultOrder: [NotchTabItem] = [.player, .shelf, .calendar, .weather, .clipboard, .apps, .clock, .systemStats, .bluetooth]

    /// The player was called "home" until it was renamed for what it actually
    /// is, so a tab order or button action stored by an older build still
    /// carries that name. Mapping it here covers every way the value is read
    /// back — `Defaults` decodes these by raw value, and `Codable` goes through
    /// this initialiser too.
    init?(rawValue: String) {
        let name = rawValue == "home" ? "player" : rawValue
        guard let match = Self.allCases.first(where: { $0.rawValue == name }) else { return nil }
        self = match
    }

    var view: NotchViews {
        switch self {
        case .player: return .player
        case .shelf: return .shelf
        case .calendar: return .calendar
        case .weather: return .weather
        case .clipboard: return .clipboard
        case .apps: return .apps
        case .clock: return .clock
        case .systemStats: return .systemStats
        case .bluetooth: return .bluetooth
        }
    }

    var label: String {
        switch self {
        case .player: return NSLocalizedString("tab_player", comment: "Notch tab: Player")
        case .shelf: return NSLocalizedString("tab_shelf", comment: "Notch tab: Shelf")
        case .calendar: return NSLocalizedString("tab_calendar", comment: "Notch tab: Calendar")
        case .weather: return NSLocalizedString("tab_weather", comment: "Notch tab: Weather")
        case .clipboard: return NSLocalizedString("tab_clipboard", comment: "Notch tab: Clipboard")
        case .apps: return NSLocalizedString("tab_apps", comment: "Notch tab: Apps")
        case .clock: return NSLocalizedString("tab_clock", comment: "Notch tab: Clock")
        case .systemStats: return NSLocalizedString("tab_stats", comment: "Notch tab: System stats")
        case .bluetooth: return NSLocalizedString("tab_bluetooth", comment: "Notch tab: Bluetooth devices")
        }
    }

    var iconName: String {
        switch self {
        case .player: return "play.circle.fill"
        case .shelf: return "tray.fill"
        case .calendar: return "calendar"
        case .weather: return "cloud.sun.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .apps: return "square.grid.2x2.fill"
        case .clock: return "clock.fill"
        case .systemStats: return "chart.line.uptrend.xyaxis"
        case .bluetooth: return "wave.3.right.circle.fill"
        }
    }

    /// The header accessory that already leads to this destination, if any.
    ///
    /// A feature that puts an icon in the header does not also get a tab: the
    /// icon is the way in, so a tab beside it would be a second control for the
    /// same thing eating strip width. The destination itself still exists — it
    /// is just reached from the icon.
    var headerCounterpart: NotchHeaderItem? {
        switch self {
        case .weather: return .weather
        case .bluetooth: return .bluetooth
        case .systemStats: return .systemStats
        default: return nil
        }
    }

    /// True when this tab is suppressed only because its header icon is showing.
    @MainActor
    var isShadowedByHeaderItem: Bool {
        guard let counterpart = headerCounterpart else { return false }
        return counterpart.isEnabled
    }

    /// The player is always available; the rest follow their feature's preference.
    @MainActor
    var isEnabled: Bool {
        guard !isShadowedByHeaderItem else { return false }

        switch self {
        case .player: return true
        case .shelf: return Defaults[.boringShelf]
        case .calendar: return Defaults[.showCalendar]
        case .weather: return Defaults[.weatherEnabled] && Defaults[.weatherShowInNotch]
        case .clipboard: return Defaults[.clipboardHistoryEnabled] && Defaults[.clipboardShowInNotch]
        case .apps: return Defaults[.appSwitcherEnabled] && Defaults[.appSwitcherShowTab]
        case .clock: return Defaults[.clockEnabled] && Defaults[.clockShowInNotch]
        case .systemStats: return Defaults[.systemStatsEnabled]
        case .bluetooth: return Defaults[.bluetoothNotchIcon]
        }
    }
}

// MARK: - Resolution helpers

@MainActor
enum NotchLayoutResolver {
    /// Stored order, repaired against the current set of cases.
    ///
    /// Items added in a newer version are appended rather than lost, and items
    /// removed from the enum are dropped, so an old stored array stays valid.
    static func headerItems() -> [NotchHeaderItem] {
        reconcile(Defaults[.notchHeaderItems], all: NotchHeaderItem.allCases)
            .filter(\.isEnabled)
    }

    static func tabItems() -> [NotchTabItem] {
        reconcile(Defaults[.notchTabOrder], all: NotchTabItem.allCases)
            .filter(\.isEnabled)
    }

    static func reconcile<T: Hashable>(_ stored: [T], all: [T]) -> [T] {
        let valid = Set(all)
        var result = stored.filter { valid.contains($0) }
        let present = Set(result)
        result.append(contentsOf: all.filter { !present.contains($0) })
        return result
    }
}
