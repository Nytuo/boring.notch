//
//  HelperCapability.swift
//  BoringNotchXPCHelper
//
//  F-01: privileged capability groups. None of these methods exist on the
//  protocol yet (window control, notification reply, keystroke posting, PTY,
//  low power mode — F-30/F-31/F-15/F-24/F-33/F-23 respectively); this is the
//  gate future work must call through before doing anything privileged.
//
//  The app is sandboxed and the helper isn't, so the helper can't reliably
//  read the app's `Defaults` store (it lives inside the app's container,
//  which the unsandboxed helper has no standing access to without Full Disk
//  Access). Instead the app pushes its capability toggles to the helper
//  explicitly over `updateCapabilities(_:with:)` on connect and whenever a
//  toggle changes; the helper holds them in memory only and re-checks before
//  every privileged call, same as a pull would, just push-driven instead of
//  the plan's literal "re-reads" wording. See FORK_NOTES.md.
//

import Foundation

enum HelperCapability: String, CaseIterable {
    case axWindows
    case axNotifications
    case input
    case pty
    case power
}

final class HelperCapabilityGate {
    static let shared = HelperCapabilityGate()

    private let queue = DispatchQueue(label: "BoringNotchXPCHelper.capabilityGate")
    private var enabled: Set<HelperCapability> = []

    private init() {}

    func update(_ settings: [String: Bool]) {
        queue.sync {
            var next: Set<HelperCapability> = []
            for (key, value) in settings where value {
                if let capability = HelperCapability(rawValue: key) {
                    next.insert(capability)
                }
            }
            enabled = next
        }
    }

    func isAllowed(_ capability: HelperCapability) -> Bool {
        queue.sync { enabled.contains(capability) }
    }
}
