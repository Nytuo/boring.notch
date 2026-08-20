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

    func boardWidgets() -> [BoardWidgetDescriptor] {
        [BoardWidgetDescriptor(
            localID: "countdown",
            extensionID: manifest.id,
            title: manifest.name,
            iconName: manifest.iconName,
            defaultSize: .small,
            content: AnyView(BoardCaffeineWidgetView())
        )]
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

    func boardWidgets() -> [BoardWidgetDescriptor] {
        [BoardWidgetDescriptor(
            localID: "summary",
            extensionID: manifest.id,
            title: manifest.name,
            iconName: manifest.iconName,
            defaultSize: .small,
            content: AnyView(BoardWeatherWidgetView())
        )]
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

    func boardWidgets() -> [BoardWidgetDescriptor] {
        [BoardWidgetDescriptor(
            localID: "pinned",
            extensionID: manifest.id,
            title: manifest.name,
            iconName: manifest.iconName,
            defaultSize: .wide,
            content: AnyView(BoardClipboardWidgetView())
        )]
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
        capabilities: [.liveActivity, .externalData],
        requiredPermissions: [.accessibility]
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

// MARK: - VPN status

@MainActor
final class VPNStatusExtension: BoringExtension {
    let manifest = ExtensionManifest(
        id: "com.theboringteam.extension.vpn",
        name: NSLocalizedString("extension_vpn_name", comment: "Extension name: VPN Status"),
        summary: NSLocalizedString("extension_vpn_summary", comment: "Extension summary: VPN Status"),
        iconName: "lock.shield.fill",
        capabilities: [.liveActivity, .headerAccessory]
    )

    var isEnabled: Bool {
        get { Defaults[.vpnStatusEnabled] }
        set { Defaults[.vpnStatusEnabled] = newValue }
    }

    var settingsView: AnyView? {
        AnyView(VStack(alignment: .leading, spacing: 6) {
            Defaults.Toggle(key: .vpnStatusLiveActivity) {
                Text("Show closed-notch banner on connect")
            }
            Defaults.Toggle(key: .vpnStatusHeaderIcon) {
                Text("Show header icon while connected")
            }
        })
    }

    func activate() {
        VPNStatusManager.shared.start()
    }

    func deactivate() {
        VPNStatusManager.shared.stop()
    }
}

// MARK: - Meeting mic indicator

@MainActor
final class MeetingExtension: BoringExtension {
    let manifest = ExtensionManifest(
        id: "com.theboringteam.extension.meeting",
        name: NSLocalizedString("extension_meeting_name", comment: "Extension name: Meeting Mic Indicator"),
        summary: NSLocalizedString("extension_meeting_summary", comment: "Extension summary: Meeting Mic Indicator"),
        iconName: "mic.fill",
        capabilities: [.liveActivity]
        // No microphone permission requested: reading whether the input
        // device "is running somewhere" via CoreAudio is device-state, not
        // audio capture, so it doesn't trigger — or need — the mic TCC
        // prompt. Declaring .microphone here would misrepresent what this
        // actually does.
    )

    var isEnabled: Bool {
        get { Defaults[.meetingIndicatorEnabled] }
        set { Defaults[.meetingIndicatorEnabled] = newValue }
    }

    func activate() {
        MeetingManager.shared.start()
    }

    func deactivate() {
        MeetingManager.shared.stop()
    }
}

// MARK: - AI agent progress

@MainActor
final class AgentProgressExtension: BoringExtension {
    let manifest = ExtensionManifest(
        id: "com.theboringteam.extension.agentprogress",
        name: NSLocalizedString("extension_agent_name", comment: "Extension name: AI Agent Progress"),
        summary: NSLocalizedString("extension_agent_summary", comment: "Extension summary: AI Agent Progress"),
        iconName: "sparkles",
        capabilities: [.liveActivity, .externalData]
        // Listens on a fixed loopback TCP port; nothing leaves the machine.
    )

    var isEnabled: Bool {
        get { Defaults[.agentProgressEnabled] }
        set { Defaults[.agentProgressEnabled] = newValue }
    }

    var settingsView: AnyView? {
        AnyView(AgentProgressSettingsView())
    }

    func activate() {
        AgentProgressServer.shared.start()
    }

    func deactivate() {
        AgentProgressServer.shared.stop()
    }
}

// MARK: - Voice recorder

@MainActor
final class VoiceRecorderExtension: BoringExtension {
    let manifest = ExtensionManifest(
        id: "com.theboringteam.extension.voicerecorder",
        name: NSLocalizedString("extension_voicerecorder_name", comment: "Extension name: Voice Notes"),
        summary: NSLocalizedString("extension_voicerecorder_summary", comment: "Extension summary: Voice Notes"),
        iconName: "mic.circle.fill",
        capabilities: [.liveActivity, .externalData],
        requiredPermissions: [.microphone, .speech]
    )

    var isEnabled: Bool {
        get { Defaults[.voiceRecorderEnabled] }
        set { Defaults[.voiceRecorderEnabled] = newValue }
    }

    var settingsView: AnyView? {
        AnyView(Defaults.Toggle(key: .voiceRecorderAutoTranscribe) {
            Text("Transcribe automatically after recording")
        })
    }

    func activate() {}

    func deactivate() {
        if VoiceRecorderManager.shared.isRecording {
            VoiceRecorderManager.shared.stopRecording()
        }
    }
}

// MARK: - Motion art

@MainActor
final class MotionArtExtension: BoringExtension {
    let manifest = ExtensionManifest(
        id: "com.theboringteam.extension.motionart",
        name: NSLocalizedString("extension_motionart_name", comment: "Extension name: Motion Art"),
        summary: NSLocalizedString("extension_motionart_summary", comment: "Extension summary: Motion Art"),
        iconName: "sparkles.tv",
        capabilities: []
    )

    var isEnabled: Bool {
        get { Defaults[.motionArtEnabled] }
        set { Defaults[.motionArtEnabled] = newValue }
    }

    func activate() {}

    func deactivate() {}

    func boardWidgets() -> [BoardWidgetDescriptor] {
        [BoardWidgetDescriptor(
            localID: "video",
            extensionID: manifest.id,
            title: manifest.name,
            iconName: manifest.iconName,
            defaultSize: .large,
            content: AnyView(MotionArtWidgetView())
        )]
    }
}
