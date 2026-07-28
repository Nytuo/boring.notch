//
//  ClipboardSettingsView.swift
//  boringNotch
//

import Defaults
import KeyboardShortcuts
import SwiftUI

struct ClipboardSettings: View {
    @ObservedObject private var clipboard = ClipboardManager.shared

    @Default(.clipboardHistoryEnabled) private var enabled
    @Default(.clipboardHistoryLimit) private var limit
    @Default(.clipboardPersistHistory) private var persist
    @Default(.clipboardExcludedApps) private var excludedApps

    @State private var newExclusion: String = ""

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .clipboardHistoryEnabled) {
                    Text("Enable clipboard history")
                }
                HelpText("Keeps a searchable history of what you copy.")
            } header: {
                Text("General")
            }

            Section {
                Stepper(value: $limit, in: 10...1000, step: 10) {
                    HStack {
                        Text("History limit")
                        Spacer()
                        Text("\(limit) items")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!enabled)

                Defaults.Toggle(key: .clipboardStoreImages) {
                    Text("Store images")
                }
                .disabled(!enabled)

                Defaults.Toggle(key: .clipboardPersistHistory) {
                    Text("Keep history between launches")
                }
                .disabled(!enabled)

                if persist {
                    warningBadge(
                        NSLocalizedString("clipboard_persist_warning_title", comment: "Persistence warning title"),
                        NSLocalizedString("clipboard_persist_warning_body", comment: "Persistence warning body")
                    )
                }

                HStack {
                    Text("Stored entries")
                    Spacer()
                    Text("\(clipboard.entries.count)")
                        .foregroundStyle(.secondary)
                    Button("Clear") {
                        clipboard.clearHistory()
                        clipboard.deletePersistedHistory()
                    }
                }
            } header: {
                Text("Storage")
            }

            Section {
                Defaults.Toggle(key: .clipboardIgnoreConfidential) {
                    Text("Ignore confidential content")
                }
                .disabled(!enabled)
                HelpText("Skips anything marked concealed or transient, which is how password managers flag secrets.")

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
                Text("Privacy")
            }

            Section {
                Defaults.Toggle(key: .clipboardShowInNotch) {
                    Text("Show clipboard tab in notch")
                }
                .disabled(!enabled)

                KeyboardShortcuts.Recorder("Open clipboard history", name: .clipboardHistoryPanel)
            } header: {
                Text("Access")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Clipboard")
    }
}
