//
//  NotificationLiveActivity.swift
//  boringNotch
//

import Defaults
import SwiftUI

/// Banner shown across the closed notch when a system notification arrives.
struct NotificationLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var watcher = NotificationWatcher.shared

    let closedNotchHeight: CGFloat

    var body: some View {
        if let notification = watcher.latest {
            NotchBannerLayout {
                HStack(spacing: 8) {
                    if let bundleID = notification.bundleIdentifier {
                        AppIcon(for: bundleID)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "bell.badge.fill")
                            .foregroundStyle(Color.effectiveAccent)
                            .imageScale(.medium)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(notification.title)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if Defaults[.notificationsShowBody], let body = notification.body {
                            Text(body)
                                .font(.caption2)
                                .foregroundStyle(.gray)
                                .lineLimit(1)
                        } else if let appName = notification.appName {
                            Text(appName)
                                .font(.caption2)
                                .foregroundStyle(.gray)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 10)

                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width + 2 * liveActivityEdgeMargin)

                HStack(spacing: 6) {
                    Text(notification.receivedAt, style: .time)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.gray)
                    if watcher.canReply(to: notification.id) {
                        NotificationReplyButton(notificationID: notification.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
            }
            .frame(height: closedNotchHeight, alignment: .center)
        }
    }
}

/// F-31: reply affordance, shown only while `NotificationWatcher` still has
/// the banner's AX element retained (see that class's "Reply" section for
/// why this is best-effort and unverified against a live banner).
private struct NotificationReplyButton: View {
    let notificationID: UUID

    @State private var showReply = false
    @State private var text = ""

    var body: some View {
        Button {
            showReply = true
        } label: {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.caption2)
                .foregroundStyle(Color.effectiveAccent)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showReply, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                TextField(NSLocalizedString("notification_reply_placeholder", comment: "Placeholder for the notification reply field"), text: $text)
                    .textFieldStyle(.plain)
                    .onSubmit(send)
                Button(NSLocalizedString("notification_reply_send", comment: "Send a notification reply")) {
                    send()
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(10)
            .frame(width: 240)
        }
    }

    private func send() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        NotificationWatcher.shared.reply(to: notificationID, text: text)
        text = ""
        showReply = false
    }
}
