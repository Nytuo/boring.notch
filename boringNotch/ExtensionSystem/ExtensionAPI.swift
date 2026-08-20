//
//  ExtensionAPI.swift
//  boringNotch
//
//  The contract every Boring Notch extension implements.
//
//  Extensions are registered in-process rather than loaded from external
//  bundles. That is a deliberate constraint, not a stopgap: the app is
//  sandboxed and notarised, and `dlopen`-ing third-party code would break the
//  sandbox guarantees and invalidate the signature. This API gives features a
//  uniform lifecycle, settings surface and enable/disable switch, and is the
//  layer a future out-of-process (XPC) extension host would sit behind.
//

import SwiftUI

// MARK: - Capabilities

/// What an extension contributes to the app. Used to describe extensions in
/// the settings list and to decide which host surfaces to query.
enum ExtensionCapability: String, CaseIterable, Codable, Hashable {
    /// Draws a banner across the closed notch.
    case liveActivity
    /// Contributes a tab to the opened notch.
    case notchTab
    /// Contributes an accessory to the opened notch header.
    case headerAccessory
    /// Contributes items to the menu bar extra.
    case menuBarItem
    /// Registers a global keyboard shortcut.
    case keyboardShortcut
    /// Reads or writes data outside the app (network, pasteboard, file system).
    case externalData

    var label: String {
        switch self {
        case .liveActivity:
            return NSLocalizedString("capability_live_activity", comment: "Extension capability: live activity")
        case .notchTab:
            return NSLocalizedString("capability_notch_tab", comment: "Extension capability: notch tab")
        case .headerAccessory:
            return NSLocalizedString("capability_header_accessory", comment: "Extension capability: header accessory")
        case .menuBarItem:
            return NSLocalizedString("capability_menu_bar", comment: "Extension capability: menu bar item")
        case .keyboardShortcut:
            return NSLocalizedString("capability_shortcut", comment: "Extension capability: keyboard shortcut")
        case .externalData:
            return NSLocalizedString("capability_external_data", comment: "Extension capability: external data access")
        }
    }

    var iconName: String {
        switch self {
        case .liveActivity: return "rectangle.topthird.inset.filled"
        case .notchTab: return "square.on.square"
        case .headerAccessory: return "menubar.rectangle"
        case .menuBarItem: return "menubar.arrow.up.rectangle"
        case .keyboardShortcut: return "keyboard"
        case .externalData: return "network"
        }
    }
}

// MARK: - Permissions

/// A system permission an extension may need. Declared on the manifest so
/// the extensions gallery can disclose what enabling a feature will ask for
/// *before* the TCC prompt appears (F-02).
enum Permission: Hashable {
    case accessibility
    case screenRecording
    case microphone
    case speech
    case location
    case fullDiskAccess
    case inputMonitoring
    case automation(bundleID: String)

    var label: String {
        switch self {
        case .accessibility:
            return NSLocalizedString("permission_accessibility", comment: "Permission: Accessibility")
        case .screenRecording:
            return NSLocalizedString("permission_screen_recording", comment: "Permission: Screen Recording")
        case .microphone:
            return NSLocalizedString("permission_microphone", comment: "Permission: Microphone")
        case .speech:
            return NSLocalizedString("permission_speech", comment: "Permission: Speech Recognition")
        case .location:
            return NSLocalizedString("permission_location", comment: "Permission: Location")
        case .fullDiskAccess:
            return NSLocalizedString("permission_full_disk_access", comment: "Permission: Full Disk Access")
        case .inputMonitoring:
            return NSLocalizedString("permission_input_monitoring", comment: "Permission: Input Monitoring")
        case .automation:
            return NSLocalizedString("permission_automation", comment: "Permission: Automation")
        }
    }

    var iconName: String {
        switch self {
        case .accessibility: return "figure.wave.circle"
        case .screenRecording: return "rectangle.inset.filled.and.person.filled"
        case .microphone: return "mic.fill"
        case .speech: return "waveform"
        case .location: return "location.fill"
        case .fullDiskAccess: return "externaldrive.fill"
        case .inputMonitoring: return "keyboard.fill"
        case .automation: return "gearshape.2.fill"
        }
    }

    /// Deep link to the relevant System Settings pane, following the pattern
    /// `NotificationWatcher.needsAccessibility` already uses.
    var systemSettingsURL: URL? {
        switch self {
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speech:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        case .location:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
        case .fullDiskAccess:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        case .inputMonitoring:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        case .automation:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        }
    }
}

// MARK: - Manifest

/// Static description of an extension, shown in the extensions settings list.
struct ExtensionManifest: Identifiable, Hashable {
    /// Reverse-DNS identifier, stable across versions.
    let id: String
    let name: String
    let summary: String
    let author: String
    let version: String
    let iconName: String
    let capabilities: Set<ExtensionCapability>
    /// System permissions this extension will request once enabled. Shown in
    /// the extensions gallery so enabling discloses this before the TCC
    /// prompt appears (F-02).
    let requiredPermissions: Set<Permission>
    /// `true` for extensions shipped with the app, which cannot be uninstalled.
    let isBuiltIn: Bool

    init(
        id: String,
        name: String,
        summary: String,
        author: String = "The Boring Team",
        version: String = "1.0",
        iconName: String,
        capabilities: Set<ExtensionCapability>,
        requiredPermissions: Set<Permission> = [],
        isBuiltIn: Bool = true
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.author = author
        self.version = version
        self.iconName = iconName
        self.capabilities = capabilities
        self.requiredPermissions = requiredPermissions
        self.isBuiltIn = isBuiltIn
    }
}

// MARK: - Extension protocol

@MainActor
protocol BoringExtension: AnyObject {
    var manifest: ExtensionManifest { get }

    /// Backing preference for this extension's on/off state.
    ///
    /// Extensions reuse their feature's existing preference rather than
    /// introducing a parallel one, so the extensions list and the feature's own
    /// settings tab can never disagree.
    var isEnabled: Bool { get set }

    /// Called when the extension is switched on, and at launch if already on.
    func activate()

    /// Called when the extension is switched off.
    func deactivate()

    /// Settings UI for this extension, shown inline in the extensions list.
    /// `nil` when the extension has its own top-level settings tab instead.
    @ViewBuilder var settingsView: AnyView? { get }

    /// Tab this extension contributes, if any.
    var notchTab: NotchTabItem? { get }

    /// Widgets this extension can place on the board (F-11), if any.
    /// Rebuilt on every call so board content stays live rather than a
    /// stale snapshot from whenever the extension was registered.
    func boardWidgets() -> [BoardWidgetDescriptor]
}

extension BoringExtension {
    var settingsView: AnyView? { nil }
    var notchTab: NotchTabItem? { nil }
    func boardWidgets() -> [BoardWidgetDescriptor] { [] }
}
