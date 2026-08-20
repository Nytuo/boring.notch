//
//  KeystrokeSoundSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct KeystrokeSoundSettings: View {
    @Default(.keystrokeSoundsEnabled) private var enabled
    @Default(.capabilityInputEnabled) private var capabilityEnabled
    @Default(.keystrokeSoundsVolume) private var volume
    @Default(.keystrokeSoundsExcludedApps) private var excludedApps

    @State private var newExclusion: String = ""
    @State private var showDisclosure = false

    var body: some View {
        Form {
            Section {
                Toggle("Play a sound on every keystroke", isOn: Binding(
                    get: { enabled },
                    set: { newValue in
                        if newValue {
                            showDisclosure = true
                        } else {
                            enabled = false
                            capabilityEnabled = false
                        }
                    }
                ))
            } header: {
                Text("Keystroke Sounds")
            } footer: {
                HelpText("This observes every keystroke locally, on this Mac, to decide when to play a sound. Nothing about what you type is ever stored, logged, or transmitted — the helper only ever computes a coarse 0-11 pitch bucket from the key and immediately discards everything else.")
            }

            Section {
                Slider(value: $volume, in: 0...1) {
                    Text("Volume")
                }
                .disabled(!enabled)
            }

            Section {
                if excludedApps.isEmpty {
                    Text("No apps excluded")
                        .foregroundStyle(.secondary)
                }
                ForEach(excludedApps, id: \.self) { bundleID in
                    HStack {
                        Text(bundleID)
                            .font(.callout)
                        Spacer()
                        Button {
                            excludedApps.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("Bundle identifier to ignore", text: $newExclusion)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let trimmed = newExclusion.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, !excludedApps.contains(trimmed) else { return }
                        excludedApps.append(trimmed)
                        newExclusion = ""
                    }
                    .disabled(newExclusion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Excluded Apps")
            } footer: {
                HelpText("Keystroke sounds are skipped entirely while one of these apps is frontmost — useful for password managers or anything else where you'd rather this stay off.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Keystroke Sounds")
        .alert(
            NSLocalizedString("keystroke_disclosure_title", comment: "Disclosure alert title before enabling keystroke sounds"),
            isPresented: $showDisclosure
        ) {
            Button(NSLocalizedString("keystroke_disclosure_allow", comment: "Confirm enabling keystroke sounds"), role: .destructive) {
                capabilityEnabled = true
                enabled = true
            }
            Button(NSLocalizedString("keystroke_disclosure_cancel", comment: "Cancel enabling keystroke sounds"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("keystroke_disclosure_message", comment: "Explains what the keystroke observer does and does not do, before the Input Monitoring prompt"))
        }
    }
}
