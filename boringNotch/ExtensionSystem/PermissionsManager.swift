//
//  PermissionsManager.swift
//  boringNotch
//
//  F-02: single place owning permission status + request for the
//  `Permission` cases a `BoringExtension` can declare on its manifest.
//  Extends the existing `PermissionRequestView` onboarding pattern rather
//  than replacing it — this supplies the status/request logic that view's
//  callers wire up.
//

import AVFoundation
import AppKit
import CoreLocation
import Speech
import SwiftUI

enum PermissionStatus {
    case granted
    case denied
    /// No supported way to check status ahead of the OS prompt (screen
    /// recording, full disk access, input monitoring, automation). Treated
    /// as "ask the user to check System Settings" rather than guessed at.
    case unknown
}

@MainActor
final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    private init() {}

    /// Best-effort synchronous status. Never claims a capability the
    /// platform doesn't expose a status API for (screen recording, full disk
    /// access, input monitoring, automation all report `.unknown`).
    func status(for permission: Permission) -> PermissionStatus {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .denied, .restricted: return .denied
            case .notDetermined: return .unknown
            @unknown default: return .unknown
            }
        case .speech:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .granted
            case .denied, .restricted: return .denied
            case .notDetermined: return .unknown
            @unknown default: return .unknown
            }
        case .location:
            switch CLLocationManager().authorizationStatus {
            case .authorizedAlways: return .granted
            case .denied, .restricted: return .denied
            case .notDetermined: return .unknown
            @unknown default: return .unknown
            }
        case .screenRecording, .fullDiskAccess, .inputMonitoring, .automation:
            return .unknown
        }
    }

    /// Triggers the OS prompt where one exists; otherwise opens the
    /// relevant System Settings pane, matching
    /// `NotificationWatcher.needsAccessibility` / `ScreenshotManager.needsFolderAccess`.
    func request(_ permission: Permission) {
        switch permission {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        case .speech:
            SFSpeechRecognizer.requestAuthorization { _ in }
        case .location:
            CLLocationManager().requestAlwaysAuthorization()
        case .screenRecording, .fullDiskAccess, .inputMonitoring, .automation:
            openSystemSettings(for: permission)
        }
    }

    func openSystemSettings(for permission: Permission) {
        guard let url = permission.systemSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }
}
