//
//  NotificationSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct NotificationSettings: View {
    @ObservedObject private var watcher = NotificationWatcher.shared

    @Default(.notificationsEnabled) private var enabled
    @Default(.notificationsExcludedApps) private var excludedApps

    @State private var newExclusion: String = ""

    var body: some View {
        Form {
            warningBadge(
                NSLocalizedString("notifications_caveat_title", comment: "Notification support caveat title"),
                NSLocalizedString("notifications_caveat_body", comment: "Notification support caveat body")
            )

            Section {
                Defaults.Toggle(key: .notificationsEnabled) {
                    Text("Show notifications in the notch")
                }
            } header: {
                Text("General")
            }

            if enabled {
                Section {
                    statusRow
                } header: {
                    Text("Status")
                }
            }

            Section {
                Defaults.Toggle(key: .notificationsLiveActivity) {
                    Text("Show live activity")
                }
                .disabled(!enabled)
                Defaults.Toggle(key: .notificationsShowBody) {
                    Text("Show notification body")
                }
                .disabled(!enabled)
            } header: {
                Text("Appearance")
            }

            Section {
                ForEach(excludedApps, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button {
                            excludedApps.removeAll { $0 == name }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("App name to ignore", text: $newExclusion)
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
                Text("Ignored Apps")
            } footer: {
                HelpText("Matched against the app name shown in the notification banner.")
            }

            Section {
                HStack {
                    Text("Captured notifications")
                    Spacer()
                    Text("\(watcher.recent.count)")
                        .foregroundStyle(.secondary)
                    Button("Clear") { watcher.clearHistory() }
                }
            } header: {
                Text("History")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Notifications")
    }

    @ViewBuilder
    private var statusRow: some View {
        if watcher.needsAccessibility {
            HStack(spacing: 12) {
                Image(systemName: "lock.trianglebadge.exclamationmark")
                    .font(.system(size: 22))
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility permission required")
                        .font(.headline)
                    Text("Notification text is read through the Accessibility API.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Grant") { watcher.requestAccessibilityPermission() }
            }
        } else if watcher.isUnsupportedLayout {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Could not read Notification Center")
                        .font(.headline)
                    Text("This macOS version may have changed its layout. Retrying automatically.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.green)
                Text("Watching for notifications")
                Spacer()
            }
        }
    }
}
