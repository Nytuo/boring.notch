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
    @Default(.clockPomodoroWorkMinutes) private var pomodoroWorkMinutes
    @Default(.clockPomodoroShortBreakMinutes) private var pomodoroShortBreakMinutes
    @Default(.clockPomodoroLongBreakMinutes) private var pomodoroLongBreakMinutes
    @Default(.clockPomodoroCyclesBeforeLongBreak) private var pomodoroCyclesBeforeLongBreak
    @Default(.clockPomodoroCompletedSessions) private var pomodoroCompletedSessions

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

            Section {
                Stepper(value: $pomodoroWorkMinutes, in: 1...120) {
                    HStack {
                        Text("Work session")
                        Spacer()
                        Text("\(pomodoroWorkMinutes) min")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!enabled)

                Stepper(value: $pomodoroShortBreakMinutes, in: 1...60) {
                    HStack {
                        Text("Short break")
                        Spacer()
                        Text("\(pomodoroShortBreakMinutes) min")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!enabled)

                Stepper(value: $pomodoroLongBreakMinutes, in: 1...120) {
                    HStack {
                        Text("Long break")
                        Spacer()
                        Text("\(pomodoroLongBreakMinutes) min")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!enabled)

                Stepper(value: $pomodoroCyclesBeforeLongBreak, in: 1...12) {
                    HStack {
                        Text("Work sessions before a long break")
                        Spacer()
                        Text("\(pomodoroCyclesBeforeLongBreak)")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!enabled)

                Defaults.Toggle(key: .clockPomodoroAutoAdvance) {
                    Text("Start the next phase automatically")
                }
                .disabled(!enabled)

                HStack {
                    Text("Work sessions completed")
                    Spacer()
                    Text("\(pomodoroCompletedSessions)")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Pomodoro")
            } footer: {
                HelpText("A work/break cycle built on the timer above. Runs as its own mode in the clock tab.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Clock")
    }
}
