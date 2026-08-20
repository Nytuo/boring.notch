//
//  MediaControllerProtocol.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import AppKit
import Combine

protocol MediaControllerProtocol: ObservableObject {
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { get }
    var supportsVolumeControl: Bool { get }
    var supportsFavorite: Bool { get }
    /// F-20: whether `queue()` can return something real. Apple Music's
    /// AppleScript dictionary has no first-class "queue" object — this is
    /// approximated from the remaining tracks in `current playlist`, which
    /// only exists for playlist-sourced playback (not radio/streaming
    /// stations). Spotify's dictionary exposes no track enumeration at all.
    /// Default `false`, same reasoning as Now Playing returning `nil`.
    var supportsQueue: Bool { get }

    func setFavorite(_ favorite: Bool) async
    func play() async
    func pause() async
    func seek(to time: Double) async
    func nextTrack() async
    func previousTrack() async
    func togglePlay() async
    func toggleShuffle() async
    func toggleRepeat() async
    func setVolume(_ level: Double) async
    func isActive() -> Bool
    func updatePlaybackInfo() async
    /// Upcoming tracks, nearest first. `nil` when unsupported or unavailable
    /// right now (e.g. Apple Music playing a radio station).
    func queue() async -> [QueueItem]?
    /// Jumps to the item at `index` in the array `queue()` last returned.
    /// A no-op for controllers that don't support it.
    func playItem(at index: Int) async
}

extension MediaControllerProtocol {
    var supportsQueue: Bool { false }
    func queue() async -> [QueueItem]? { nil }
    func playItem(at index: Int) async {}
}
