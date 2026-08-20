//
//  LauncherSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct LauncherSettings: View {
    @ObservedObject private var launcher = UniversalLauncherManager.shared

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .launcherEnabled) {
                    Text("Show launcher tab in notch")
                }
            } header: {
                Text("Launcher")
            } footer: {
                HelpText("A search field over installed apps and a handful of in-app quick actions. Doesn't search files — apps and actions only.")
            }

            Section {
                Button("Rescan Applications") {
                    launcher.rescan()
                }
                Text("\(launcher.installedApps.count) apps found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Launcher")
        .onAppear {
            launcher.ensureScanned()
        }
    }
}
