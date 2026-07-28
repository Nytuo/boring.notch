//
//  BluetoothSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct BluetoothSettings: View {
    @Default(.bluetoothLiveActivity) private var enabled

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .bluetoothLiveActivity) {
                    Text("Show Bluetooth live activity")
                }
                HelpText("Displays a banner in the notch when a Bluetooth device connects or disconnects.")
            } header: {
                Text("General")
            }

            Section {
                Defaults.Toggle(key: .bluetoothNotifyOnConnect) {
                    Text("Notify on connect")
                }
                .disabled(!enabled)
                Defaults.Toggle(key: .bluetoothNotifyOnDisconnect) {
                    Text("Notify on disconnect")
                }
                .disabled(!enabled)
                Defaults.Toggle(key: .bluetoothNotchIcon) {
                    Text("Show device battery in notch")
                }
                Defaults.Toggle(key: .bluetoothShowBatteryLevel) {
                    Text("Show battery level")
                }
                .disabled(!enabled)
                HelpText("Battery level is only available for devices that report it, such as AirPods, Magic Mouse and Magic Keyboard.")
            } header: {
                Text("Events")
            }

            Section {
                BluetoothDeviceList()
            } header: {
                Text("Connected Devices")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Bluetooth")
    }
}
