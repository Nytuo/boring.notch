//
//  AgentProgressViews.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct AgentProgressLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var server = AgentProgressServer.shared

    let closedNotchHeight: CGFloat

    private var latest: AgentStatus? { server.activeAgents.last }

    var body: some View {
        if let latest {
            NotchBannerLayout {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(latest.agentName)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(latest.toolName ?? latest.state)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 10)

                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width + 2 * liveActivityEdgeMargin)

                Image(systemName: "sparkles")
                    .imageScale(.medium)
                    .foregroundStyle(Color.effectiveAccent)
                    .symbolRenderingMode(.hierarchical)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
            }
            .frame(height: closedNotchHeight, alignment: .center)
        }
    }
}

/// Install snippet for the settings pane — a `curl` hook command that POSTs
/// the hook's own JSON payload straight through as the request body.
enum AgentInstallSnippet {
    static var hookCommand: String {
        "curl -s -X POST http://127.0.0.1:\(AgentProgressServer.port)/event -H 'Content-Type: application/json' -d @- --max-time 1 >/dev/null 2>&1 || true"
    }

    /// A ready-to-paste fragment for `~/.claude/settings.json`'s `hooks` key.
    static var settingsJSONFragment: String {
        let command = hookCommand.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {
          "hooks": {
            "PreToolUse": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "\(command)" }] }],
            "PostToolUse": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "\(command)" }] }],
            "Notification": [{ "hooks": [{ "type": "command", "command": "\(command)" }] }],
            "Stop": [{ "hooks": [{ "type": "command", "command": "\(command)" }] }]
          }
        }
        """
    }
}
