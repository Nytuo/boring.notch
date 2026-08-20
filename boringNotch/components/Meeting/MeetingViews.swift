//
//  MeetingViews.swift
//  boringNotch
//
//  F-24: "your mic is live" banner. Named `MeetingLiveActivity` for its
//  trigger condition (a known meeting app running with the mic active), not
//  because it controls the meeting — see MeetingManager's header comment for
//  why mute/leave isn't part of this pass.
//

import Defaults
import SwiftUI

struct MeetingLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var meeting = MeetingManager.shared

    let closedNotchHeight: CGFloat

    var body: some View {
        NotchBannerLayout {
            VStack(alignment: .trailing, spacing: 1) {
                Text(NSLocalizedString("meeting_mic_live", comment: "Microphone is live"))
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let appName = meeting.meetingAppName {
                    Text(appName)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 10)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 2 * liveActivityEdgeMargin)

            Image(systemName: "mic.fill")
                .imageScale(.medium)
                .foregroundStyle(.red)
                .symbolRenderingMode(.hierarchical)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
        }
        .frame(height: closedNotchHeight, alignment: .center)
    }
}
