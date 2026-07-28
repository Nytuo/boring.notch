//
//  SystemStatsSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct SystemStatsSettings: View {
    @Default(.systemStatsEnabled) private var enabled

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .systemStatsEnabled) {
                    Text("Enable system stats")
                }
                Defaults.Toggle(key: .systemStatsShowOnClosedNotch) {
                    Text("Show on the closed notch")
                }
                .disabled(!enabled)
                Defaults.Toggle(key: .systemStatsNotchIcon) {
                    Text("Show icon in the opened notch")
                }
                .disabled(!enabled)
            } header: {
                Text("System Stats")
            } footer: {
                HelpText("Keeps CPU, memory and network load beside the notch. Readings are sampled every two seconds and only while something is showing them.")
            }

            Section {
                Defaults.Toggle(key: .systemStatsShowCPU) {
                    Text("CPU usage")
                }
                .disabled(!enabled)
                Defaults.Toggle(key: .systemStatsShowMemory) {
                    Text("Memory usage")
                }
                .disabled(!enabled)
                Defaults.Toggle(key: .systemStatsShowNetwork) {
                    Text("Network throughput")
                }
                .disabled(!enabled)
            } header: {
                Text("Readings")
            } footer: {
                HelpText("CPU and memory sit to the left of the notch, network to the right.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("System Stats")
    }
}
