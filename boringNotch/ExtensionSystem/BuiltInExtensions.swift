//
//  BuiltInExtensions.swift
//  boringNotch
//
//  The features that ship with the app, expressed through the extension API.
//  Each one wraps its existing manager and preference rather than owning new
//  state, so the extensions list is a view onto the same settings.
//

import Defaults
import SwiftUI

// MARK: - Keep Awake

@MainActor
final class CaffeineExtension: BoringExtension {
    let manifest = ExtensionManifest(
        id: "com.theboringteam.extension.caffeine",
        name: NSLocalizedString("extension_caffeine_name", comment: "Extension name: Keep Awake"),
        summary: NSLocalizedString("extension_caffeine_summary", comment: "Extension summary: Keep Awake"),
        iconName: "cup.and.saucer.fill",
        capabilities: [.liveActivity, .headerAccessory, .menuBarItem, .keyboardShortcut]
    )

    var isEnabled: Bool {
        get { Defaults[.caffeineEnabled] }
        set { Defaults[.caffeineEnabled] = newValue }
    }

    func activate() {
        _ = CaffeineManager.shared
    }

    func deactivate() {
        CaffeineManager.shared.deactivate()
    }
}

// MARK: - Bluetooth

@MainActor
final class BluetoothExtension: BoringExtension {
    let manifest = ExtensionManifest(
        id: "com.theboringteam.extension.bluetooth",
        name: NSLocalizedString("extension_bluetooth_name", comment: "Extension name: Bluetooth"),
        summary: NSLocalizedString("extension_bluetooth_summary", comment: "Extension summary: Bluetooth"),
        iconName: "wave.3.right.circle",
        capabilities: [.liveActivity, .externalData]
    )

    var isEnabled: Bool {
        get { Defaults[.bluetoothLiveActivity] }
        set { Defaults[.bluetoothLiveActivity] = newValue }
    }

    func activate() {
        BluetoothManager.shared.start()
    }

    func deactivate() {
        BluetoothManager.shared.stop()
    }
}

// MARK: - Weather

@MainActor
final class WeatherExtension: BoringExtension {
    let manifest = ExtensionManifest(
        id: "com.theboringteam.extension.weather",
        name: NSLocalizedString("extension_weather_name", comment: "Extension name: Weather"),
        summary: NSLocalizedString("extension_weather_summary", comment: "Extension summary: Weather"),
        iconName: "cloud.sun.fill",
        capabilities: [.notchTab, .headerAccessory, .externalData]
    )

    var isEnabled: Bool {
        get { Defaults[.weatherEnabled] }
        set { Defaults[.weatherEnabled] = newValue }
    }

    var notchTab: NotchTabItem? { .weather }

    func activate() {
        WeatherManager.shared.start()
    }

    func deactivate() {
        WeatherManager.shared.stop()
    }
}

// MARK: - Clipboard

@MainActor
final class ClipboardExtension: BoringExtension {
    let manifest = ExtensionManifest(
        id: "com.theboringteam.extension.clipboard",
        name: NSLocalizedString("extension_clipboard_name", comment: "Extension name: Clipboard"),
        summary: NSLocalizedString("extension_clipboard_summary", comment: "Extension summary: Clipboard"),
        iconName: "doc.on.clipboard.fill",
        capabilities: [.notchTab, .keyboardShortcut, .externalData]
    )

    var isEnabled: Bool {
        get { Defaults[.clipboardHistoryEnabled] }
        set { Defaults[.clipboardHistoryEnabled] = newValue }
    }

    var notchTab: NotchTabItem? { .clipboard }

    func activate() {
        ClipboardManager.shared.start()
    }

    func deactivate() {
        ClipboardManager.shared.stop()
    }
}

// MARK: - Downloads

@MainActor
final class DownloadsExtension: BoringExtension {
    let manifest = ExtensionManifest(
        id: "com.theboringteam.extension.downloads",
        name: NSLocalizedString("extension_downloads_name", comment: "Extension name: Downloads"),
        summary: NSLocalizedString("extension_downloads_summary", comment: "Extension summary: Downloads"),
        iconName: "arrow.down.circle.fill",
        capabilities: [.liveActivity, .externalData]
    )

    var isEnabled: Bool {
        get { Defaults[.enableDownloadListener] }
        set { Defaults[.enableDownloadListener] = newValue }
    }

    func activate() {
        DownloadManager.shared.start()
    }

    func deactivate() {
        DownloadManager.shared.stop()
    }
}

// MARK: - Screenshots

@MainActor
final class ScreenshotsExtension: BoringExtension {
    let manifest = ExtensionManifest(
        id: "com.theboringteam.extension.screenshots",
        name: NSLocalizedString("extension_screenshots_name", comment: "Extension name: Screenshots"),
        summary: NSLocalizedString("extension_screenshots_summary", comment: "Extension summary: Screenshots"),
        iconName: "camera.viewfinder",
        capabilities: [.liveActivity, .externalData]
    )

    var isEnabled: Bool {
        get { Defaults[.screenshotCatcherEnabled] }
        set { Defaults[.screenshotCatcherEnabled] = newValue }
    }

    func activate() {
        ScreenshotManager.shared.start()
    }

    func deactivate() {
        ScreenshotManager.shared.stop()
    }
}

// MARK: - System stats

@MainActor
final class SystemStatsExtension: BoringExtension {
    let manifest = ExtensionManifest(
        id: "com.theboringteam.extension.systemstats",
        name: NSLocalizedString("extension_systemstats_name", comment: "Extension name: System Stats"),
        summary: NSLocalizedString("extension_systemstats_summary", comment: "Extension summary: System Stats"),
        iconName: "gauge.with.dots.needle.bottom.50percent",
        capabilities: [.liveActivity]
    )

    var isEnabled: Bool {
        get { Defaults[.systemStatsEnabled] }
        set { Defaults[.systemStatsEnabled] = newValue }
    }

    func activate() {
        SystemStatsManager.shared.start()
    }

    func deactivate() {
        SystemStatsManager.shared.stop()
    }
}

// MARK: - App switcher

@MainActor
final class AppSwitcherExtension: BoringExtension {
    let manifest = ExtensionManifest(
        id: "com.theboringteam.extension.appswitcher",
        name: NSLocalizedString("extension_appswitcher_name", comment: "Extension name: App Switcher"),
        summary: NSLocalizedString("extension_appswitcher_summary", comment: "Extension summary: App Switcher"),
        iconName: "square.grid.2x2.fill",
        capabilities: [.notchTab, .keyboardShortcut]
    )

    var isEnabled: Bool {
        get { Defaults[.appSwitcherEnabled] }
        set { Defaults[.appSwitcherEnabled] = newValue }
    }

    var notchTab: NotchTabItem? { .apps }

    func activate() {
        AppSwitcherManager.shared.start()
    }

    func deactivate() {
        AppSwitcherManager.shared.stop()
    }
}

// MARK: - Notifications

@MainActor
final class NotificationsExtension: BoringExtension {
    let manifest = ExtensionManifest(
        id: "com.theboringteam.extension.notifications",
        name: NSLocalizedString("extension_notifications_name", comment: "Extension name: Notifications"),
        summary: NSLocalizedString("extension_notifications_summary", comment: "Extension summary: Notifications"),
        iconName: "bell.badge.fill",
        capabilities: [.liveActivity, .externalData]
    )

    var isEnabled: Bool {
        get { Defaults[.notificationsEnabled] }
        set { Defaults[.notificationsEnabled] = newValue }
    }

    func activate() {
        NotificationWatcher.shared.start()
    }

    func deactivate() {
        NotificationWatcher.shared.stop()
    }
}
