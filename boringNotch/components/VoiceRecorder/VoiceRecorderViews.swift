//
//  VoiceRecorderViews.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct VoiceRecorderLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var recorder = VoiceRecorderManager.shared

    let closedNotchHeight: CGFloat

    var body: some View {
        NotchBannerLayout {
            VStack(alignment: .trailing, spacing: 1) {
                Text(NSLocalizedString("voice_recording", comment: "Recording a voice note"))
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(ClockManager.formatDuration(recorder.elapsedTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 10)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 2 * liveActivityEdgeMargin)

            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .opacity(recorder.isRecording ? 1 : 0.3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
        }
        .frame(height: closedNotchHeight, alignment: .center)
    }
}
