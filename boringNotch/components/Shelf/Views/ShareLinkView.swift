//
//  ShareLinkView.swift
//  boringNotch
//

import AppKit
import SwiftUI

struct ShareLinkView: View {
    @ObservedObject private var server = LocalShareServer.shared

    var body: some View {
        VStack(spacing: 10) {
            if let url = server.shareURL, let qrImage = QRCodeGenerator.image(for: url.absoluteString) {
                Image(nsImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 140, height: 140)

                Text(url.absoluteString)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if let expiresAt = server.activeShare?.expiresAt {
                    Text(String(format: NSLocalizedString("share_link_expires", comment: "Shows when a local share link expires, %@ is a relative time"), Self.relativeTimeString(expiresAt)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button(NSLocalizedString("share_link_copy", comment: "Copy the local share link")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }
                    Button(NSLocalizedString("share_link_stop", comment: "Stop the local share")) {
                        server.stopSharing()
                    }
                }
            } else {
                Text(NSLocalizedString("share_link_failed", comment: "Local share could not start"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 200)
    }

    private static func relativeTimeString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
