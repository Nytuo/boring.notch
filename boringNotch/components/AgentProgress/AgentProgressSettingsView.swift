//
//  AgentProgressSettingsView.swift
//  boringNotch
//

import AppKit
import SwiftUI

struct AgentProgressSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(format: NSLocalizedString("agent_settings_intro", comment: "Explains how to wire up an agent's hooks, %d is the port number"), Int(AgentProgressServer.port)))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(NSLocalizedString("agent_settings_snippet_label", comment: "Label above the pasteable hook config snippet"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: true) {
                Text(AgentInstallSnippet.settingsJSONFragment)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.25))
            )
            .frame(maxHeight: 160)

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(AgentInstallSnippet.settingsJSONFragment, forType: .string)
            } label: {
                Text(NSLocalizedString("agent_settings_copy", comment: "Copy the hook config snippet"))
            }

            HelpText("Merge this into the \"hooks\" key of ~/.claude/settings.json. Nothing leaves the machine — it's a local loopback connection only.")
        }
        .padding(.vertical, 4)
    }
}
