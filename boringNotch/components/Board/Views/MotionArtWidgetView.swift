//
//  MotionArtWidgetView.swift
//  boringNotch
//

import AVFoundation
import AppKit
import SwiftUI

struct MotionArtWidgetView: View {
    @ObservedObject private var controller = MotionArtController.shared

    var body: some View {
        Group {
            if controller.videoURL != nil {
                MotionArtPlayerView(player: controller.player)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { controller.attach() }
        .onDisappear { controller.detach() }
        .contextMenu {
            Button(NSLocalizedString("motion_art_choose", comment: "Choose a motion art video")) {
                controller.chooseVideo()
            }
            if controller.videoURL != nil {
                Button(NSLocalizedString("motion_art_clear", comment: "Remove the motion art video"), role: .destructive) {
                    controller.clearVideo()
                }
            }
        }
    }

    private var emptyState: some View {
        Button {
            controller.chooseVideo()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                Text(NSLocalizedString("motion_art_choose", comment: "Choose a motion art video"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }
}

/// `AVPlayerLayer` in an `NSView` — SwiftUI/AVKit's `VideoPlayer` always
/// draws transport controls, which a looping decorative background doesn't
/// want.
private struct MotionArtPlayerView: NSViewRepresentable {
    let player: AVQueuePlayer?

    func makeNSView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: PlayerContainerView, context: Context) {
        nsView.playerLayer.player = player
    }

    final class PlayerContainerView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = CALayer()
            layer?.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }
    }
}
