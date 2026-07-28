//
//  ClockSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct ClockSettings: View {
    @Default(.clockEnabled) private var enabled
    @Default(.clockFollowSystemFormat) private var followSystemFormat
    @Default(.clockDefaultTimerMinutes) private var defaultTimerMinutes

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .clockEnabled) {
                    Text("Enable clock, timer and stopwatch")
                }
                Defaults.Toggle(key: .clockShowInNotch) {
                    Text("Show clock tab in notch")
                }
                .disabled(!enabled)
            } header: {
                Text("Clock")
            } footer: {
                HelpText("Adds a tab with a clock, a countdown timer and a stopwatch. Timers and the stopwatch keep running while the notch is closed.")
            }

            Section {
                Defaults.Toggle(key: .clockShowSeconds) {
                    Text("Show seconds")
                }
                .disabled(!enabled)
                Defaults.Toggle(key: .clockShowAnalogFace) {
                    Text("Show analog dial")
                }
                .disabled(!enabled)
                Defaults.Toggle(key: .clockFollowSystemFormat) {
                    Text("Use the system time format")
                }
                .disabled(!enabled)
                Defaults.Toggle(key: .clockUse24Hour) {
                    Text("24-hour clock")
                }
                .disabled(!enabled || followSystemFormat)
            } header: {
                Text("Appearance")
            }

            Section {
                Stepper(value: $defaultTimerMinutes, in: 1...180) {
                    HStack {
                        Text("Default timer length")
                        Spacer()
                        Text("\(defaultTimerMinutes) min")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!enabled)

                Defaults.Toggle(key: .clockShowOnClosedNotch) {
                    Text("Show a running timer or stopwatch on the closed notch")
                }
                .disabled(!enabled)

                Defaults.Toggle(key: .clockTimerSound) {
                    Text("Play a sound when a timer ends")
                }
                .disabled(!enabled)

                Defaults.Toggle(key: .clockTimerOpensNotch) {
                    Text("Open the notch when a timer ends")
                }
                .disabled(!enabled)
            } header: {
                Text("Timer")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Clock")
    }
}
