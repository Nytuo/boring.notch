//
//  CaffeineSettingsView.swift
//  boringNotch
//

import Defaults
import KeyboardShortcuts
import SwiftUI

struct CaffeineSettings: View {
    @ObservedObject private var caffeine = CaffeineManager.shared

    @Default(.caffeineEnabled) private var caffeineEnabled
    @Default(.caffeineDefaultDuration) private var defaultDuration
    @Default(.caffeineLiveActivity) private var liveActivity

    /// Custom duration in minutes, surfaced when the user wants something that
    /// is not one of the presets.
    @State private var customMinutes: Int = 45

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .caffeineEnabled) {
                    Text("Enable Keep Awake")
                }
                HelpText("Prevents this Mac from going to sleep while active.")
            } header: {
                Text("General")
            }

            Section {
                statusRow
            } header: {
                Text("Status")
            }

            Section {
                Picker("Default duration", selection: $defaultDuration) {
                    ForEach(CaffeineDuration.presets) { preset in
                        Text(preset.localizedString).tag(preset)
                    }
                    if !CaffeineDuration.presets.contains(.minutes(customMinutes)) {
                        Text(CaffeineDuration.minutes(customMinutes).localizedString)
                            .tag(CaffeineDuration.minutes(customMinutes))
                    }
                }
                .disabled(!caffeineEnabled)

                Stepper(value: $customMinutes, in: 1...1440, step: 5) {
                    HStack {
                        Text("Custom duration")
                        Spacer()
                        Text(CaffeineDuration.minutes(customMinutes).localizedString)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!caffeineEnabled)

                Button("Start for \(CaffeineDuration.minutes(customMinutes).localizedString)") {
                    caffeine.activate(for: .minutes(customMinutes))
                }
                .disabled(!caffeineEnabled)

                Defaults.Toggle(key: .caffeineAllowDisplaySleep) {
                    Text("Allow display to sleep")
                }
                .disabled(!caffeineEnabled)
                HelpText("Keeps the system awake but lets the screen turn off, like `caffeinate -i`.")

                Defaults.Toggle(key: .caffeineActivateOnLaunch) {
                    Text("Activate on launch")
                }
                .disabled(!caffeineEnabled)
            } header: {
                Text("Duration")
            }

            Section {
                Defaults.Toggle(key: .caffeineNotchIcon) {
                    Text("Show cup button in notch")
                }
                .disabled(!caffeineEnabled)
                HelpText("Adds a cup to the opened notch. Click to start or stop, right-click to pick a duration.")

                Defaults.Toggle(key: .caffeineNotchCountdown) {
                    Text("Keep remaining time on the closed notch")
                }
                .disabled(!caffeineEnabled)
                HelpText("Leaves the countdown visible on the notch as a reminder while nothing else is showing there.")

                Defaults.Toggle(key: .caffeineShowInMenuBar) {
                    Text("Add controls to the Boring Notch menu")
                }
                .disabled(!caffeineEnabled)

                Defaults.Toggle(key: .caffeineLiveActivity) {
                    Text("Show live activity in notch")
                }
                .disabled(!caffeineEnabled)

                Defaults.Toggle(key: .caffeineShowCountdown) {
                    Text("Show countdown in notch")
                }
                .disabled(!caffeineEnabled || !liveActivity)
            } header: {
                Text("Appearance")
            }

            Section {
                KeyboardShortcuts.Recorder("Toggle Keep Awake", name: .toggleCaffeine)
            } header: {
                Text("Shortcut")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Keep Awake")
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: caffeine.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.system(size: 22))
                .foregroundStyle(caffeine.isActive ? Color.effectiveAccent : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(caffeine.isActive ? "Keeping your Mac awake" : "Not active")
                    .font(.headline)
                if caffeine.isActive {
                    if let formatted = caffeine.formattedRemaining {
                        Text("\(formatted) remaining")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Until turned off")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Your Mac will sleep according to Energy Saver settings.")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if caffeine.isActive {
                if caffeine.expiresAt != nil {
                    Button("+15 min") { caffeine.extend(by: 15 * 60) }
                }
                Button("Stop") { caffeine.deactivate() }
            } else {
                Button("Start") { caffeine.activate(for: defaultDuration) }
                    .disabled(!caffeineEnabled)
            }
        }
        .padding(.vertical, 4)
    }
}
