//
//  ExtensionsSettingsView.swift
//  boringNotch
//

import SwiftUI

struct ExtensionsSettings: View {
    @ObservedObject private var registry = ExtensionRegistry.shared

    var body: some View {
        Form {
            Section {
                ForEach(registry.extensions, id: \.manifest.id) { extensionItem in
                    row(for: extensionItem.manifest)
                }
            } header: {
                Text("Installed Extensions")
            } footer: {
                HelpText("Extensions bundled with Boring Notch. Turning one off stops it running and hides everything it contributes.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Extensions")
        // Registry state lives in Defaults, so nudge the view when it changes.
        .id(registry.revision)
    }

    @ViewBuilder
    private func row(for manifest: ExtensionManifest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: manifest.iconName)
                    .font(.system(size: 22))
                    .foregroundStyle(Color.effectiveAccent)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(manifest.name)
                            .font(.headline)
                        if manifest.isBuiltIn {
                            customBadge(text: NSLocalizedString("extension_builtin", comment: "Badge for bundled extensions"))
                        }
                    }
                    Text(manifest.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: registry.binding(for: manifest.id))
                    .labelsHidden()
            }

            HStack(spacing: 6) {
                ForEach(Array(manifest.capabilities).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { capability in
                    Label(capability.label, systemImage: capability.iconName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 5)
                        .background(Color(nsColor: .secondarySystemFill))
                        .clipShape(.capsule)
                }
            }
            .padding(.leading, 42)

            Text("v\(manifest.version) · \(manifest.author)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 42)
        }
        .padding(.vertical, 4)
    }
}
