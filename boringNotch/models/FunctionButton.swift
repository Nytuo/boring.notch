//
//  FunctionButton.swift
//  boringNotch
//
//  User-configurable action buttons shown in the opened notch.
//

import AppKit
import Defaults
import SwiftUI

/// What a function button does when clicked.
///
/// Every case here works inside the app sandbox without additional
/// entitlements. Actions that would need Automation access to System Events or
/// Finder (sleep, empty trash, toggle dark mode) are deliberately absent —
/// they would prompt for permission and fail for most users.
enum FunctionButtonAction: Codable, Hashable {
    /// Launch or focus an application by bundle identifier.
    case openApp(bundleID: String)
    /// Open a URL, which also covers `shortcuts://` and custom app schemes.
    case openURL(string: String)
    /// Run a Shortcuts workflow by name, via the `shortcuts://` scheme.
    case runShortcut(name: String)
    /// Start the screen saver.
    case screenSaver
    /// Switch the opened notch to a tab.
    case openTab(tab: NotchTabItem)
    /// Toggle the Keep Awake session.
    case toggleCaffeine
    /// Toggle microphone mute.
    case toggleMicrophone

    var iconName: String {
        switch self {
        case .openApp: return "app.badge"
        case .openURL: return "link"
        case .runShortcut: return "square.stack.3d.up"
        case .screenSaver: return "moon.stars"
        case .openTab(let tab): return tab.iconName
        case .toggleCaffeine: return "cup.and.saucer"
        case .toggleMicrophone: return "mic.slash"
        }
    }

    var localizedDescription: String {
        switch self {
        case .openApp(let bundleID):
            return bundleID
        case .openURL(let string):
            return string
        case .runShortcut(let name):
            return name
        case .screenSaver:
            return NSLocalizedString("function_action_screensaver", comment: "Function button: start screen saver")
        case .openTab(let tab):
            return tab.label
        case .toggleCaffeine:
            return NSLocalizedString("function_action_caffeine", comment: "Function button: toggle Keep Awake")
        case .toggleMicrophone:
            return NSLocalizedString("function_action_microphone", comment: "Function button: toggle microphone")
        }
    }
}

/// One configured button.
struct FunctionButton: Identifiable, Codable, Hashable, Defaults.Serializable {
    let id: UUID
    var title: String
    /// SF Symbol name. Empty means "use the action's default icon".
    var iconName: String
    var action: FunctionButtonAction

    init(id: UUID = UUID(), title: String, iconName: String = "", action: FunctionButtonAction) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.action = action
    }

    var effectiveIconName: String {
        iconName.isEmpty ? action.iconName : iconName
    }
}

// MARK: - Execution

@MainActor
enum FunctionButtonRunner {
    static func run(_ button: FunctionButton) {
        switch button.action {
        case .openApp(let bundleID):
            openApp(bundleID: bundleID)

        case .openURL(let string):
            guard let url = URL(string: string) else {
                NSLog("⚠️ Function button: '\(string)' is not a valid URL")
                return
            }
            NSWorkspace.shared.open(url)

        case .runShortcut(let name):
            // The Shortcuts URL scheme needs the name percent-encoded, since
            // shortcut names routinely contain spaces.
            guard let encoded = name.addingPercentEncoding(
                    withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)")
            else {
                NSLog("⚠️ Function button: could not build a URL for shortcut '\(name)'")
                return
            }
            NSWorkspace.shared.open(url)

        case .screenSaver:
            let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())

        case .openTab(let tab):
            // A button must not strand the panel on a destination whose feature
            // has been switched off. A tab hidden only because its header icon
            // replaces it is still a valid place to go.
            guard tab.isEnabled || tab.isShadowedByHeaderItem else { return }
            withAnimation(.smooth) {
                BoringViewCoordinator.shared.currentView = tab.view
            }

        case .toggleCaffeine:
            CaffeineManager.shared.toggle()

        case .toggleMicrophone:
            let coordinator = BoringViewCoordinator.shared
            coordinator.toggleSneakPeek(
                status: true,
                type: .mic,
                value: coordinator.currentMicStatus ? 0 : 1
            )
        }
    }

    private static func openApp(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            NSLog("⚠️ Function button: no application found for '\(bundleID)'")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
