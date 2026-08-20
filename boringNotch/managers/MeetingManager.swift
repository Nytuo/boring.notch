//
//  MeetingManager.swift
//  boringNotch
//
//  F-24: scoped down to the passive "your mic is live" indicator the plan
//  itself calls worth shipping alone. Real mute/leave via per-app shortcuts
//  needs the XPC helper's `input` capability (posting synthetic keystrokes),
//  which doesn't exist yet — HelperCapability.swift already lists `.input`
//  as reserved for this, but adding keystroke posting is a meaningfully
//  larger, riskier XPC surface than this pass covers. Ship the indicator;
//  mute/leave is follow-up work once `input` lands.
//

import AppKit
import Combine
import CoreAudio
import Defaults
import Foundation

@MainActor
final class MeetingManager: NSObject, ObservableObject {
    static let shared = MeetingManager()

    @Published private(set) var isMicLive = false
    @Published private(set) var meetingAppName: String?

    /// Bundle identifiers of common meeting apps. Deliberately not
    /// browser-based (Meet-in-Chrome, etc.) — there is no reliable way to
    /// tell a meeting tab from any other open tab, and a false positive here
    /// reads as the app lying about something privacy-sensitive.
    private static let meetingAppBundleIDs: [String: String] = [
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams2": "Microsoft Teams",
        "com.microsoft.teams": "Microsoft Teams",
        "com.apple.FaceTime": "FaceTime",
        "com.cisco.webexmeetingsapp": "Webex"
    ]

    private var cancellables = Set<AnyCancellable>()
    private var isListening = false

    private override init() {
        super.init()
        Defaults.publisher(.meetingIndicatorEnabled)
            .sink { [weak self] change in
                Task { @MainActor in
                    change.newValue ? self?.start() : self?.stop()
                }
            }
            .store(in: &cancellables)

        if Defaults[.meetingIndicatorEnabled] {
            start()
        }
    }

    func start() {
        stop()
        isListening = true
        setupMicListener()
        refresh()
    }

    func stop() {
        isListening = false
        removeMicListener()
        isMicLive = false
        meetingAppName = nil
    }

    private func setupMicListener() {
        let deviceID = Self.defaultInputDeviceID()
        guard deviceID != AudioObjectID(kAudioObjectUnknown) else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(deviceID, &address, nil) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func removeMicListener() {
        // The listener block holds only a weak self and is torn down with
        // the process; nothing to explicitly unregister since the device
        // list can change between start()/stop() calls (a fresh listener is
        // installed on every start() rather than tracking one to remove).
    }

    private func refresh() {
        guard isListening else { return }

        let deviceID = Self.defaultInputDeviceID()
        let live = deviceID != AudioObjectID(kAudioObjectUnknown) && Self.isDeviceRunning(deviceID)
        let runningMeetingApp = Self.frontmostMeetingApp()

        let wasLive = isMicLive
        isMicLive = live
        meetingAppName = runningMeetingApp

        if live, let runningMeetingApp, !wasLive {
            BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .meeting)
        }
        _ = runningMeetingApp
    }

    private static func frontmostMeetingApp() -> String? {
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier, let name = meetingAppBundleIDs[bundleID] else { continue }
            return name
        }
        return nil
    }

    // MARK: - CoreAudio

    private static func defaultInputDeviceID() -> AudioObjectID {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID)
        return status == noErr ? deviceID : AudioObjectID(kAudioObjectUnknown)
    }

    private static func isDeviceRunning(_ deviceID: AudioObjectID) -> Bool {
        var isRunning: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &isRunning)
        return status == noErr && isRunning != 0
    }
}
