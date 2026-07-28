//
//  DownloadSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct DownloadSettings: View {
    @ObservedObject private var downloads = DownloadManager.shared

    @Default(.enableDownloadListener) private var enabled
    @Default(.downloadsFolderBookmark) private var bookmark
    @Default(.selectedDownloadIndicatorStyle) private var indicatorStyle
    @Default(.selectedDownloadIconStyle) private var iconStyle

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableDownloadListener) {
                    Text("Show download progress")
                }
                HelpText("Detects in-progress downloads by watching for the temporary files browsers create.")
            } header: {
                Text("General")
            }

            if enabled && downloads.needsFolderAccess {
                warningBadge(
                    NSLocalizedString("downloads_access_title", comment: "Downloads folder access required"),
                    NSLocalizedString("downloads_access_body", comment: "Explanation of why access is required")
                )
                Section {
                    Button("Grant access to Downloads folder") {
                        downloads.requestDownloadsFolderAccess()
                    }
                }
            }

            Section {
                Defaults.Toggle(key: .enableSafariDownloads) {
                    Text("Safari")
                }
                .disabled(!enabled)
                Defaults.Toggle(key: .enableChromiumDownloads) {
                    Text("Chromium browsers")
                }
                .disabled(!enabled)
                HelpText("Chrome, Brave, Edge, Vivaldi, Opera and Arc.")
                Defaults.Toggle(key: .enableFirefoxDownloads) {
                    Text("Firefox")
                }
                .disabled(!enabled)
            } header: {
                Text("Browsers")
            }

            Section {
                Picker("Indicator style", selection: $indicatorStyle) {
                    Text("Progress bar").tag(DownloadIndicatorStyle.progress)
                    Text("Percentage").tag(DownloadIndicatorStyle.percentage)
                }
                .disabled(!enabled)

                Picker("Icon style", selection: $iconStyle) {
                    Text("Browser icon").tag(DownloadIconStyle.onlyAppIcon)
                    Text("Download icon").tag(DownloadIconStyle.onlyIcon)
                    Text("Both").tag(DownloadIconStyle.iconAndAppIcon)
                }
                .disabled(!enabled)
            } header: {
                Text("Appearance")
            }

            Section {
                if downloads.activeDownloads.isEmpty {
                    Text("No downloads in progress")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(downloads.activeDownloads) { download in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(download.fileName)
                                Text(download.browser.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(download.formattedProgress)
                                .foregroundStyle(.secondary)
                                .font(.callout.monospacedDigit())
                        }
                    }
                }
            } header: {
                Text("Active Downloads")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Downloads")
    }
}
