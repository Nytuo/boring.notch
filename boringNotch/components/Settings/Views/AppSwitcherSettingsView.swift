//
//  AppSwitcherSettingsView.swift
//  boringNotch
//

import Defaults
import KeyboardShortcuts
import SwiftUI

struct AppSwitcherSettings: View {
    @ObservedObject private var switcher = AppSwitcherManager.shared
    @Default(.appSwitcherEnabled) private var enabled

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .appSwitcherEnabled) {
                    Text("Enable app switcher")
                }
                HelpText("Shows your running apps in the notch, most recently used first.")
            } header: {
                Text("General")
            }

            Section {
                Defaults.Toggle(key: .appSwitcherShowTab) {
                    Text("Show apps tab in notch")
                }
                .disabled(!enabled)

                Defaults.Toggle(key: .appSwitcherIncludeMinimized) {
                    Text("Include hidden apps")
                }
                .disabled(!enabled)

                KeyboardShortcuts.Recorder("Open app switcher", name: .toggleAppSwitcher)
            } header: {
                Text("Behavior")
            }

            Section {
                HStack {
                    Text("Running apps")
                    Spacer()
                    Text("\(switcher.apps.count)")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Status")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("App Switcher")
    }
}
