//
//  BluetoothManager.swift
//  boringNotch
//
//  Watches classic Bluetooth connect/disconnect events and surfaces them as
//  notch live activities.
//

import AppKit
import Combine
import Defaults
import CoreBluetooth
import IOBluetooth
import IOKit
import SwiftUI

// MARK: - Model

struct BluetoothDeviceInfo: Identifiable, Equatable {
    /// The device address string, e.g. `00-11-22-33-44-55`. Stable per device.
    let id: String
    let name: String
    /// SF Symbol chosen from the device's Bluetooth class-of-device bits.
    let iconName: String
    /// 0...1, or `nil` when the device does not report a battery level.
    var batteryLevel: Double?

    var batteryPercentText: String? {
        guard let batteryLevel else { return nil }
        return "\(Int((batteryLevel * 100).rounded()))%"
    }
}

/// A connection change worth showing in the notch.
struct BluetoothEvent: Equatable {
    let device: BluetoothDeviceInfo
    let connected: Bool
    let timestamp: Date
}

// MARK: - Manager

@MainActor
final class BluetoothManager: NSObject, ObservableObject {
    static let shared = BluetoothManager()

    @Published private(set) var connectedDevices: [BluetoothDeviceInfo] = []
    @Published private(set) var lastEvent: BluetoothEvent?

    private var connectNotification: IOBluetoothUserNotification?
    /// Disconnect notifications are registered per device on connect; keep them
    /// so they can be unregistered when the device goes away.
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var batteryRefreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    /// Set while the off-thread IOBluetooth warm-up is in flight.
    private var isStarting = false

    private override init() {
        super.init()

        Defaults.publisher(.bluetoothLiveActivity)
            .sink { [weak self] change in
                Task { @MainActor in
                    if change.newValue {
                        self?.start()
                    } else {
                        self?.stop()
                    }
                }
            }
            .store(in: &cancellables)

        if Defaults[.bluetoothLiveActivity] {
            start()
        }
    }

    // MARK: Lifecycle

    func start() {
        guard connectNotification == nil, !isStarting else { return }
        isStarting = true

        // The first IOBluetooth call spins up a coordinator that blocks on a
        // semaphore until macOS resolves the Bluetooth privacy prompt — which
        // the user may never answer. On the main thread, during launch, that
        // hangs the whole app before a window is ever drawn, so the warm-up
        // happens off it and the real work waits for it to come back.
        Task.detached(priority: .utility) {
            _ = IOBluetoothDevice.pairedDevices()
            await MainActor.run {
                BluetoothManager.shared.beginWatching()
            }
        }
    }

    /// Second half of `start()`, once IOBluetooth is known to answer promptly.
    private func beginWatching() {
        // Cleared by `stop()`, which is how a warm-up that outlived its reason
        // is discarded.
        guard isStarting else { return }
        isStarting = false
        guard connectNotification == nil, Defaults[.bluetoothLiveActivity] else { return }

        // Seed with what is already connected so the list is correct at launch,
        // without announcing devices the user connected before we started.
        refreshConnectedDevices(announce: false)

        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceDidConnect(_:device:))
        )

        BluetoothLEBatteryReader.shared.onUpdate = { [weak self] in
            self?.refreshBatteryLevels()
        }
        BluetoothLEBatteryReader.shared.start()

        startBatteryRefresh()
    }

    func stop() {
        // A warm-up still in flight must not start watching after this.
        isStarting = false
        connectNotification?.unregister()
        connectNotification = nil
        for notification in disconnectNotifications.values {
            notification.unregister()
        }
        disconnectNotifications.removeAll()
        batteryRefreshTask?.cancel()
        batteryRefreshTask = nil
        BluetoothLEBatteryReader.shared.stop()
        connectedDevices = []
        lastEvent = nil
    }

    // MARK: Notifications

    @objc private func deviceDidConnect(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        Task { @MainActor in
            self.handleConnect(device)
        }
    }

    @objc private func deviceDidDisconnect(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        Task { @MainActor in
            self.handleDisconnect(device)
        }
    }

    private func handleConnect(_ device: IOBluetoothDevice) {
        guard let info = Self.makeInfo(from: device) else { return }

        if !disconnectNotifications.keys.contains(info.id) {
            disconnectNotifications[info.id] = device.register(
                forDisconnectNotification: self,
                selector: #selector(deviceDidDisconnect(_:device:))
            )
        }

        if let index = connectedDevices.firstIndex(where: { $0.id == info.id }) {
            connectedDevices[index] = info
        } else {
            connectedDevices.append(info)
        }

        announce(BluetoothEvent(device: info, connected: true, timestamp: Date()))

        // Battery is not populated the instant a device connects; re-read it
        // shortly after so the activity can fill the value in.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.refreshBatteryLevels()
        }
    }

    private func handleDisconnect(_ device: IOBluetoothDevice) {
        guard let info = Self.makeInfo(from: device) else { return }

        disconnectNotifications[info.id]?.unregister()
        disconnectNotifications[info.id] = nil
        connectedDevices.removeAll { $0.id == info.id }

        announce(BluetoothEvent(device: info, connected: false, timestamp: Date()))
    }

    private func announce(_ event: BluetoothEvent) {
        guard Defaults[.bluetoothLiveActivity] else { return }
        if event.connected && !Defaults[.bluetoothNotifyOnConnect] { return }
        if !event.connected && !Defaults[.bluetoothNotifyOnDisconnect] { return }

        lastEvent = event
        BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .bluetooth)
    }

    // MARK: Device discovery

    private func refreshConnectedDevices(announce shouldAnnounce: Bool) {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        var devices: [BluetoothDeviceInfo] = []

        for device in paired where device.isConnected() {
            guard let info = Self.makeInfo(from: device) else { continue }
            devices.append(info)

            if !disconnectNotifications.keys.contains(info.id) {
                disconnectNotifications[info.id] = device.register(
                    forDisconnectNotification: self,
                    selector: #selector(deviceDidDisconnect(_:device:))
                )
            }
        }

        connectedDevices = devices
        refreshBatteryLevels()

        if shouldAnnounce, let first = devices.first {
            announce(BluetoothEvent(device: first, connected: true, timestamp: Date()))
        }
    }

    private static func makeInfo(from device: IOBluetoothDevice) -> BluetoothDeviceInfo? {
        guard let address = device.addressString else { return nil }
        let name = device.name ?? device.nameOrAddress ?? address
        return BluetoothDeviceInfo(
            id: address,
            name: name,
            iconName: symbolName(
                major: device.deviceClassMajor,
                minor: device.deviceClassMinor
            ),
            batteryLevel: nil
        )
    }

    /// Maps Bluetooth class-of-device bits to an SF Symbol.
    ///
    /// Values come from the Bluetooth assigned-numbers spec (Baseband,
    /// "Class of Device"); IOBluetooth exposes them pre-shifted.
    private static func symbolName(major: BluetoothDeviceClassMajor, minor: BluetoothDeviceClassMinor) -> String {
        switch Int(major) {
        case 0x01: // Computer
            return "laptopcomputer"
        case 0x02: // Phone
            return "iphone"
        case 0x04: // Audio/Video
            switch Int(minor) {
            case 0x01, 0x02: return "headset"      // headset / hands-free
            case 0x05: return "hifispeaker.fill"   // loudspeaker
            case 0x06: return "headphones"
            case 0x07: return "airpodspro"         // portable audio
            case 0x0A: return "tv"                 // video display
            default: return "headphones"
            }
        case 0x05: // Peripheral — keyboard/pointing bits live in the minor field
            let pointing = Int(minor) & 0x20
            let keyboard = Int(minor) & 0x10
            if keyboard != 0 && pointing != 0 { return "keyboard.badge.ellipsis" }
            if keyboard != 0 { return "keyboard" }
            if pointing != 0 { return "magicmouse" }
            // Remaining minor codes describe joysticks/gamepads.
            switch Int(minor) & 0x0F {
            case 0x01, 0x02: return "gamecontroller"
            case 0x05: return "gamecontroller.fill"
            case 0x06: return "pencil.tip"
            default: return "dot.radiowaves.right"
            }
        case 0x06: // Imaging
            return "printer"
        case 0x07: // Wearable
            return "applewatch"
        case 0x08: // Toy
            return "teddybear"
        case 0x09: // Health
            return "heart.text.square"
        default:
            return "dot.radiowaves.right"
        }
    }

    // MARK: Battery

    private func startBatteryRefresh() {
        batteryRefreshTask?.cancel()
        batteryRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refreshBatteryLevels()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Fills in battery levels from the IO Registry.
    ///
    /// There is no Bluetooth API for this; Apple devices publish it as
    /// `BatteryPercent*` properties on their HID service nodes, keyed by the
    /// same address IOBluetooth reports.
    private func refreshBatteryLevels() {
        BluetoothLEBatteryReader.shared.refresh()

        let levels = BluetoothBatteryReader.readLevels()
        let leLevels = BluetoothLEBatteryReader.shared.levels
        guard !levels.isEmpty || !leLevels.isEmpty else { return }

        for index in connectedDevices.indices {
            let key = connectedDevices[index].id.lowercased()
            // The registry is keyed by address, the GATT reader by name, since
            // CoreBluetooth never exposes the address.
            if let level = levels[key] ?? leLevels[connectedDevices[index].name.lowercased()] {
                connectedDevices[index].batteryLevel = level
            }
        }

        // Keep the banner in sync if it is showing the device being updated.
        if let event = lastEvent,
           let level = levels[event.device.id.lowercased()]
            ?? leLevels[event.device.name.lowercased()],
           event.device.batteryLevel != level {
            var device = event.device
            device.batteryLevel = level
            lastEvent = BluetoothEvent(
                device: device,
                connected: event.connected,
                timestamp: event.timestamp
            )
        }
    }
}

// MARK: - Battery reading

enum BluetoothBatteryReader {
    /// Returns `[lowercased-address: 0...1]` for every device that reports one.
    ///
    /// Addresses are normalised to `xx-xx-…` to match `IOBluetoothDevice`, since
    /// registry entries use a mix of separators and cases.
    static func readLevels() -> [String: Double] {
        var results: [String: Double] = [:]

        var iterator: io_iterator_t = 0
        // A single root-level recursive search: battery-reporting nodes live
        // under several different service classes depending on the device.
        let match = IOServiceMatching("IOHIDDevice")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == KERN_SUCCESS else {
            return results
        }
        defer { IOObjectRelease(iterator) }

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }

            guard let address = stringProperty(entry, "DeviceAddress")
                    ?? stringProperty(entry, "BD_ADDR") else { continue }

            guard let percent = batteryPercent(entry) else { continue }
            results[normalize(address)] = percent
        }

        return results
    }

    private static func batteryPercent(_ entry: io_registry_entry_t) -> Double? {
        // Prefer the combined value; fall back to the lowest of the individual
        // pods so the user sees the one that will die first.
        if let combined = numberProperty(entry, "BatteryPercentCombined") {
            return combined / 100.0
        }
        if let single = numberProperty(entry, "BatteryPercent") {
            return single / 100.0
        }
        let sides = ["BatteryPercentLeft", "BatteryPercentRight"]
            .compactMap { numberProperty(entry, $0) }
            .filter { $0 > 0 }
        if let lowest = sides.min() {
            return lowest / 100.0
        }
        return nil
    }

    private static func stringProperty(_ entry: io_registry_entry_t, _ key: String) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(
            entry, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }
        return value as? String
    }

    private static func numberProperty(_ entry: io_registry_entry_t, _ key: String) -> Double? {
        guard let value = IORegistryEntryCreateCFProperty(
            entry, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    private static func normalize(_ address: String) -> String {
        address
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
    }
}

// MARK: - Battery over BLE

/// Reads battery levels straight from the devices, over Bluetooth LE.
///
/// The IO Registry only carries `BatteryPercent` for Apple's own accessories.
/// Everything else — mice, keyboards, headsets from other makers — publishes it
/// as the standard GATT Battery Service (0x180F) instead, which is where macOS
/// itself gets the figure it shows in System Settings. Reading that service is
/// the only way to see those levels.
///
/// Devices are matched by name: CoreBluetooth identifies peripherals by an
/// opaque per-machine UUID, with no way back to the Bluetooth address the rest
/// of this file works in.
@MainActor
final class BluetoothLEBatteryReader: NSObject {
    static let shared = BluetoothLEBatteryReader()

    private static let batteryService = CBUUID(string: "180F")
    private static let batteryCharacteristic = CBUUID(string: "2A19")

    /// `[lowercased device name: 0...1]`.
    private(set) var levels: [String: Double] = [:]
    /// Called whenever a level arrives or changes.
    var onUpdate: (() -> Void)?

    private var central: CBCentralManager?
    /// CoreBluetooth drops peripherals it is not handed a strong reference to.
    private var peripherals: [UUID: CBPeripheral] = [:]

    private override init() {
        super.init()
    }

    func start() {
        guard central == nil else { return }
        // The main queue keeps every callback on the actor this class lives on.
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func stop() {
        for peripheral in peripherals.values {
            central?.cancelPeripheralConnection(peripheral)
        }
        peripherals.removeAll()
        levels.removeAll()
        central = nil
    }

    /// Picks up anything already connected and asks it for a fresh reading.
    func refresh() {
        guard let central, central.state == .poweredOn else { return }

        for peripheral in central.retrieveConnectedPeripherals(withServices: [Self.batteryService]) {
            peripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self

            switch peripheral.state {
            case .connected:
                readBattery(from: peripheral)
            default:
                central.connect(peripheral, options: nil)
            }
        }
    }

    private func readBattery(from peripheral: CBPeripheral) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.batteryService }) else {
            peripheral.discoverServices([Self.batteryService])
            return
        }
        guard let characteristic = service.characteristics?
            .first(where: { $0.uuid == Self.batteryCharacteristic })
        else {
            peripheral.discoverCharacteristics([Self.batteryCharacteristic], for: service)
            return
        }
        peripheral.readValue(for: characteristic)
    }

    private func store(_ level: Double, for peripheral: CBPeripheral) {
        guard let name = peripheral.name?.lowercased() else { return }
        guard levels[name] != level else { return }
        levels[name] = level
        onUpdate?()
    }
}

extension BluetoothLEBatteryReader: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            guard central.state == .poweredOn else { return }
            refresh()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            peripheral.discoverServices([Self.batteryService])
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            peripherals.removeValue(forKey: peripheral.identifier)
            if let name = peripheral.name?.lowercased() {
                levels.removeValue(forKey: name)
                onUpdate?()
            }
        }
    }
}

extension BluetoothLEBatteryReader: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard let service = peripheral.services?.first(where: { $0.uuid == Self.batteryService }) else { return }
            peripheral.discoverCharacteristics([Self.batteryCharacteristic], for: service)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            guard let characteristic = service.characteristics?
                .first(where: { $0.uuid == Self.batteryCharacteristic })
            else { return }

            peripheral.readValue(for: characteristic)
            // Most devices push changes, which saves polling them.
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            guard characteristic.uuid == Self.batteryCharacteristic,
                  let byte = characteristic.value?.first
            else { return }
            store(min(1, Double(byte) / 100.0), for: peripheral)
        }
    }
}
