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

                HStack {
                    Text(notification.receivedAt, style: .time)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
            }
            .frame(height: closedNotchHeight, alignment: .center)
        }
    }
}
