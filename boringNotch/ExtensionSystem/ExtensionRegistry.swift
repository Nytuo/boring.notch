//
//  ExtensionRegistry.swift
//  boringNotch
//

import Combine
import Defaults
import SwiftUI

@MainActor
final class ExtensionRegistry: ObservableObject {
    static let shared = ExtensionRegistry()

    /// Registered extensions, in registration order.
    @Published private(set) var extensions: [any BoringExtension] = []

    /// Bumped whenever an extension is toggled, so SwiftUI lists re-read the
    /// `isEnabled` values, which live in Defaults rather than in `@Published`
    /// storage here.
    @Published private(set) var revision = 0

    private var hasRegisteredBuiltIns = false

    private init() {}

    // MARK: Registration

    func register(_ newExtension: any BoringExtension) {
        let identifier = newExtension.manifest.id
        guard !extensions.contains(where: { $0.manifest.id == identifier }) else {
            NSLog("⚠️ Extensions: '\(identifier)' is already registered")
            return
        }
        extensions.append(newExtension)

        if newExtension.isEnabled {
            newExtension.activate()
        }
    }

    /// Registers the extensions that ship with the app. Safe to call twice.
    func registerBuiltInExtensions() {
        guard !hasRegisteredBuiltIns else { return }
        hasRegisteredBuiltIns = true

        register(CaffeineExtension())
        register(BluetoothExtension())
        register(WeatherExtension())
        register(ClipboardExtension())
        register(DownloadsExtension())
        register(ScreenshotsExtension())
        register(SystemStatsExtension())
        register(AppSwitcherExtension())
        register(NotificationsExtension())
        register(VPNStatusExtension())
        register(MeetingExtension())
        register(AgentProgressExtension())
        register(VoiceRecorderExtension())
        register(MotionArtExtension())
    }

    // MARK: Lookup

    func extensionWithID(_ id: String) -> (any BoringExtension)? {
        extensions.first { $0.manifest.id == id }
    }

    func isEnabled(_ id: String) -> Bool {
        extensionWithID(id)?.isEnabled ?? false
    }

    func setEnabled(_ id: String, _ enabled: Bool) {
        guard let target = extensionWithID(id) else { return }
        guard target.isEnabled != enabled else { return }

        target.isEnabled = enabled
        if enabled {
            target.activate()
        } else {
            target.deactivate()
        }
        revision += 1
    }

    /// Binding suitable for a `Toggle` in the extensions list.
    func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.isEnabled(id) ?? false },
            set: { [weak self] newValue in self?.setEnabled(id, newValue) }
        )
    }
}
