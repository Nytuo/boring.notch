//
//  AudioOutputManager.swift
//  boringNotch
//
//  F-21: CoreAudio output-device enumeration and switching. Extends the
//  CoreAudio call pattern already proven in `AudioOutputRouteResolver`
//  (system-object property reads, `AudioObjectAddPropertyListenerBlock`) —
//  that file stays read-only (route → icon), this one owns the device list
//  and the actual switch, since they're different responsibilities.
//
//  AirPlay targets are not covered here — CoreAudio's device list doesn't
//  enumerate them reliably, and there's no public API to. `AudioOutputPickerView`
//  pairs this with `AVRoutePickerView` (the system AirPlay picker) rather
//  than pretending to enumerate AirPlay targets itself.
//

import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
}

@MainActor
final class AudioOutputManager: ObservableObject {
    static let shared = AudioOutputManager()

    @Published private(set) var availableDevices: [AudioOutputDevice] = []
    @Published private(set) var currentDeviceID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)

    private init() {
        refresh()
        setupListeners()
    }

    func refresh() {
        availableDevices = Self.enumerateOutputDevices()
        currentDeviceID = Self.systemOutputDeviceID()
    }

    func selectDevice(_ device: AudioOutputDevice) {
        Self.setSystemOutputDevice(device.id)
        currentDeviceID = device.id
    }

    /// For `FunctionButtonAction.cycleAudioOutput`.
    func cycleToNextDevice() {
        guard availableDevices.count > 1 else { return }
        let currentIndex = availableDevices.firstIndex { $0.id == currentDeviceID } ?? -1
        let next = availableDevices[(currentIndex + 1) % availableDevices.count]
        selectDevice(next)
    }

    private func setupListeners() {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, nil) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }

        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, nil) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: - CoreAudio calls

    private static func systemOutputDeviceID() -> AudioObjectID {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID)
        return status == noErr ? deviceID : AudioObjectID(kAudioObjectUnknown)
    }

    private static func setSystemOutputDevice(_ deviceID: AudioObjectID) {
        var mutableID = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &mutableID
        )
    }

    private static func enumerateOutputDevices() -> [AudioOutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var deviceIDs = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }

        return deviceIDs.compactMap { deviceID in
            guard hasOutputStreams(deviceID) else { return nil }
            let name = readStringProperty(deviceID: deviceID, selector: kAudioObjectPropertyName)
            guard !name.isEmpty else { return nil }
            let uid = readStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID)
            return AudioOutputDevice(id: deviceID, uid: uid, name: name)
        }
    }

    private static func hasOutputStreams(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else { return false }
        return dataSize > 0
    }

    private static func readStringProperty(deviceID: AudioObjectID, selector: AudioObjectPropertySelector) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, &value) == noErr else {
            return ""
        }
        return value as String
    }
}
