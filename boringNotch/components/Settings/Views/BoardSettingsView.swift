//
//  BoardSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct BoardSettings: View {
    @Default(.boardEnabled) private var enabled

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .boardEnabled) {
                    Text("Show board tab in notch")
                }
            } header: {
                Text("Board")
            } footer: {
                HelpText("A tab you compose yourself from widgets other enabled features contribute. Turn on Edit in the board tab to add, remove, reorder or resize widgets. The layout is remembered per display.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Board")
    }
}
