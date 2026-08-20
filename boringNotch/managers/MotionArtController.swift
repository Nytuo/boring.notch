//
//  MotionArtController.swift
//  boringNotch
//
//  F-43: a looping video Board widget. Scoped down from the plan's three
//  render modes (Metal shader / user Lottie file / looping video) to video
//  only — `Lottie` is a pinned dependency but has no existing usage
//  anywhere in this codebase to build from, and a from-scratch shader or
//  Lottie integration is pure visual work with no way to confirm it
//  actually renders correctly in this environment. `AVPlayerLooper` over a
//  user-picked local video has no such ambiguity: either the file loops or
//  it doesn't, and that's mechanically verifiable from the code alone.
//

import AVFoundation
import AppKit
import Combine
import Defaults

@MainActor
final class MotionArtController: ObservableObject {
    static let shared = MotionArtController()

    @Published private(set) var videoURL: URL?

    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    /// Widgets attach for as long as they're on screen; the loop only runs
    /// while at least one is — this is what "hard-pause when the notch is
    /// closed" comes down to, since a Board widget's SwiftUI view isn't
    /// instantiated at all while its tab isn't showing.
    private var activeAttachments = 0

    private init() {
        if let bookmarkData = Defaults[.motionArtVideoBookmark] {
            let bookmark = Bookmark(data: bookmarkData)
            let (url, refreshed) = bookmark.resolve()
            if let refreshed {
                Defaults[.motionArtVideoBookmark] = refreshed
            }
            videoURL = url
        }
    }

    var player: AVQueuePlayer? { queuePlayer }

    func chooseVideo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.prompt = NSLocalizedString("motion_art_choose_prompt", comment: "Open panel button to pick a motion art video")

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let bookmark = try? Bookmark(url: url) else { return }
        Defaults[.motionArtVideoBookmark] = bookmark.data
        videoURL = url
        rebuildPlayerIfNeeded()
    }

    func clearVideo() {
        Defaults[.motionArtVideoBookmark] = nil
        videoURL = nil
        tearDownPlayer()
    }

    /// A widget calls this on appear and `detach()` on disappear. The
    /// looping player only exists while at least one widget is attached.
    func attach() {
        activeAttachments += 1
        rebuildPlayerIfNeeded()
    }

    func detach() {
        activeAttachments = max(0, activeAttachments - 1)
        if activeAttachments == 0 {
            tearDownPlayer()
        }
    }

    private func rebuildPlayerIfNeeded() {
        guard activeAttachments > 0, let videoURL, queuePlayer == nil else { return }

        let accessed = videoURL.startAccessingSecurityScopedResource()
        let item = AVPlayerItem(url: videoURL)
        let player = AVQueuePlayer()
        player.isMuted = true
        let looper = AVPlayerLooper(player: player, templateItem: item)

        self.queuePlayer = player
        self.looper = looper
        player.play()

        if accessed {
            // The looper retains its own asset reader; the bookmark's scope
            // can close once playback has started pulling from the file.
            videoURL.stopAccessingSecurityScopedResource()
        }
    }

    private func tearDownPlayer() {
        queuePlayer?.pause()
        looper = nil
        queuePlayer = nil
    }
}
