//
//  ShortcutsSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import KeyboardShortcuts
import SwiftUI

struct Shortcuts: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Toggle Sneak Peek:", name: .toggleSneakPeek)
            } header: {
                Text("Media")
            } footer: {
                Text(
                    "Sneak Peek shows the media title and artist under the notch for a few seconds."
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            Section {
                KeyboardShortcuts.Recorder("Toggle Notch Open:", name: .toggleNotchOpen)
            }
            Section {
                KeyboardShortcuts.Recorder("Open Launcher:", name: .toggleLauncher)
            } footer: {
                Text("Needs the launcher tab turned on under Settings > Launcher.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Section {
                KeyboardShortcuts.Recorder("Left Half:", name: .snapWindowLeftHalf)
                KeyboardShortcuts.Recorder("Right Half:", name: .snapWindowRightHalf)
                KeyboardShortcuts.Recorder("Top Half:", name: .snapWindowTopHalf)
                KeyboardShortcuts.Recorder("Bottom Half:", name: .snapWindowBottomHalf)
                KeyboardShortcuts.Recorder("Top Left Quarter:", name: .snapWindowTopLeftQuarter)
                KeyboardShortcuts.Recorder("Top Right Quarter:", name: .snapWindowTopRightQuarter)
                KeyboardShortcuts.Recorder("Bottom Left Quarter:", name: .snapWindowBottomLeftQuarter)
                KeyboardShortcuts.Recorder("Bottom Right Quarter:", name: .snapWindowBottomRightQuarter)
                KeyboardShortcuts.Recorder("Maximize:", name: .snapWindowMaximize)
                KeyboardShortcuts.Recorder("Center:", name: .snapWindowCenter)
                KeyboardShortcuts.Recorder("Restore:", name: .snapWindowRestore)
            } header: {
                Text("Window Snapping")
            } footer: {
                Text("Needs \"Allow window snapping\" turned on under Advanced, which requests Accessibility permission.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Shortcuts")
    }
}
