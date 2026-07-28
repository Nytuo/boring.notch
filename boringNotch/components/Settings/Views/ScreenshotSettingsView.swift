//
//  ScreenshotSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct ScreenshotSettings: View {
    @ObservedObject private var screenshots = ScreenshotManager.shared
    @Default(.screenshotCatcherEnabled) private var enabled
    @Default(.screenshotPreviewSeconds) private var previewSeconds

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .screenshotCatcherEnabled) {
                    Text("Catch screenshots")
                }

                if enabled && screenshots.needsFolderAccess {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.badge.questionmark")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Screenshots folder access needed")
                                .font(.callout)
                            Text("macOS saves screenshots to the Desktop, which a sandboxed app cannot read until you point it there once.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Choose…") { screenshots.requestFolderAccess() }
                    }
                }

                Button("Choose screenshots folder…") {
                    screenshots.requestFolderAccess()
                }
                .disabled(!enabled)
            } header: {
                Text("Screenshots")
            } footer: {
                HelpText("Shows a screenshot in the notch as it is taken, with one-click copy, add to shelf, reveal and delete — and you can drag the preview straight into another app.")
            }

            Section {
                Defaults.Toggle(key: .screenshotAddToShelf) {
                    Text("Add to shelf automatically")
                }
                .disabled(!enabled)

                Stepper(value: $previewSeconds, in: 5...120, step: 5) {
                    HStack {
                        Text("Keep the preview for")
                        Spacer()
                        Text("\(previewSeconds)s")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!enabled)
            } header: {
                Text("Behaviour")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Screenshots")
    }
}
