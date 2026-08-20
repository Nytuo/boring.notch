//
//  AppleMusicController.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import Combine
import SwiftUI

class AppleMusicController: MediaControllerProtocol {
    // MARK: - Properties
    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: "com.apple.Music",
        playbackRate: 1
    )
    
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        return true
    }

    var supportsFavorite: Bool {
        return true
    }

    var supportsQueue: Bool {
        return true
    }

    /// Maps each `queue()` result's array index to its absolute track index
    /// in `current playlist`, for `playItem(at:)`. Stale once playback moves
    /// on, same as any "up next" list would be.
    private var lastQueuePlaylistIndices: [Int] = []

    private var notificationTask: Task<Void, Never>?
    
    // MARK: - Initialization
    init() {
        setupPlaybackStateChangeObserver()
        Task {
            if isActive() {
                await updatePlaybackInfo()
            }
        }
    }
    
    private func setupPlaybackStateChangeObserver() {
        notificationTask = Task { @Sendable [weak self] in
            let notifications = DistributedNotificationCenter.default().notifications(
                named: NSNotification.Name("com.apple.Music.playerInfo")
            )
            
            for await _ in notifications {
                await self?.updatePlaybackInfo()
            }
        }
    }
    
    deinit {
        notificationTask?.cancel()
    }
    
    // MARK: - Protocol Implementation
    func play() async {
        await executeCommand("play")
    }
    
    func pause() async {
        await executeCommand("pause")
    }
    
    func togglePlay() async {
        await executeCommand("playpause")
    }
    
    func nextTrack() async {
        await executeCommand("next track")
    }
    
    func previousTrack() async {
        await executeCommand("previous track")
    }
    
    func seek(to time: Double) async {
        await executeCommand("set player position to \(time)")
        await updatePlaybackInfo()
    }
    
    func toggleShuffle() async {
        await executeCommand("set shuffle enabled to not shuffle enabled")
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }
    
    func toggleRepeat() async {
        await executeCommand("""
            if song repeat is off then
                set song repeat to all
            else if song repeat is all then
                set song repeat to one
            else
                set song repeat to off
            end if
            """)
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }
    
    func setVolume(_ level: Double) async {
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        await executeCommand("set sound volume to \(volumePercentage)")
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }
    
    func isActive() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == "com.apple.Music" }
    }

    func setFavorite(_ favorite: Bool) async {
        let script = """
        tell application "Music"
            try
                set favorited of current track to \(favorite)
            end try
        end tell
        """
        try? await AppleScriptHelper.executeVoid(script)
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }
    
    func updatePlaybackInfo() async {
        guard let descriptor = try? await fetchPlaybackInfoAsync() else { return }
        guard descriptor.numberOfItems >= 11 else { return }
        var updatedState = self.playbackState
        
        updatedState.isPlaying = descriptor.atIndex(1)?.booleanValue ?? false
        updatedState.title = descriptor.atIndex(2)?.stringValue ?? "Unknown"
        updatedState.artist = descriptor.atIndex(3)?.stringValue ?? "Unknown"
        updatedState.album = descriptor.atIndex(4)?.stringValue ?? "Unknown"
        updatedState.currentTime = descriptor.atIndex(5)?.doubleValue ?? 0
        updatedState.duration = descriptor.atIndex(6)?.doubleValue ?? 0
        updatedState.isShuffled = descriptor.atIndex(7)?.booleanValue ?? false
        let repeatModeValue = descriptor.atIndex(8)?.int32Value ?? 0
        updatedState.repeatMode = RepeatMode(rawValue: Int(repeatModeValue)) ?? .off
        let volumePercentage = descriptor.atIndex(9)?.int32Value ?? 50
        updatedState.volume = Double(volumePercentage) / 100.0
        updatedState.artwork = descriptor.atIndex(10)?.data as Data?
        let lovedState = descriptor.atIndex(11)?.booleanValue ?? false
        updatedState.isFavorite = lovedState
        updatedState.lastUpdated = Date()
        self.playbackState = updatedState
    }
    
    /// Approximates "up next" from the remaining tracks in `current
    /// playlist`. Returns `nil` when that concept doesn't apply right now —
    /// a radio station or Apple Music streaming without a backing playlist
    /// has no `current playlist` at all, and the script's own `try` block
    /// falls through to an empty result in that case rather than throwing.
    func queue() async -> [QueueItem]? {
        guard let descriptor = try? await fetchQueueAsync(),
              descriptor.numberOfItems >= 3,
              let namesList = descriptor.atIndex(1),
              let artistsList = descriptor.atIndex(2),
              let indicesList = descriptor.atIndex(3)
        else { return nil }

        let count = namesList.numberOfItems
        guard count > 0 else { return nil }

        var items: [QueueItem] = []
        var indices: [Int] = []
        for i in 1...count {
            let name = namesList.atIndex(i)?.stringValue ?? ""
            guard !name.isEmpty else { continue }
            let artist = artistsList.atIndex(i)?.stringValue
            let playlistIndex = Int(indicesList.atIndex(i)?.int32Value ?? 0)
            items.append(QueueItem(title: name, artist: artist))
            indices.append(playlistIndex)
        }

        guard !items.isEmpty else { return nil }
        lastQueuePlaylistIndices = indices
        return items
    }

    func playItem(at index: Int) async {
        guard index >= 0, index < lastQueuePlaylistIndices.count else { return }
        let playlistIndex = lastQueuePlaylistIndices[index]
        await executeCommand("play track \(playlistIndex) of current playlist")
        await updatePlaybackInfo()
    }

    private func fetchQueueAsync() async throws -> NSAppleEventDescriptor? {
        let script = """
        tell application "Music"
            try
                set currentIndex to (index of current track)
                set thePlaylist to current playlist
                set totalTracks to count of tracks of thePlaylist
                set upcomingNames to {}
                set upcomingArtists to {}
                set upcomingIndices to {}
                set maxItems to 15
                set endIndex to currentIndex + maxItems
                if endIndex > totalTracks then set endIndex to totalTracks
                if endIndex >= (currentIndex + 1) then
                    repeat with i from (currentIndex + 1) to endIndex
                        set t to track i of thePlaylist
                        set end of upcomingNames to (name of t)
                        set end of upcomingArtists to (artist of t)
                        set end of upcomingIndices to i
                    end repeat
                end if
                return {upcomingNames, upcomingArtists, upcomingIndices}
            on error
                return {{}, {}, {}}
            end try
        end tell
        """
        return try await AppleScriptHelper.execute(script)
    }

    // MARK: - Private Methods

    private func executeCommand(_ command: String) async {
        let script = "tell application \"Music\" to \(command)"
        try? await AppleScriptHelper.executeVoid(script)
    }
    
    private func fetchPlaybackInfoAsync() async throws -> NSAppleEventDescriptor? {
        let script = """
        tell application "Music"
            set isRunning to true
            try
                set playerState to player state is playing
                set currentTrackName to name of current track
                set currentTrackArtist to artist of current track
                set currentTrackAlbum to album of current track
                set trackPosition to player position
                set trackDuration to duration of current track
                set shuffleState to shuffle enabled
                set repeatState to song repeat
                if repeatState is off then
                    set repeatValue to 1
                else if repeatState is one then
                    set repeatValue to 2
                else if repeatState is all then
                    set repeatValue to 3
                end if

                try
                    set artData to data of artwork 1 of current track
                on error
                    set artData to ""
                end try
                
                set currentVolume to sound volume
                set favoriteState to favorited of current track
                return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, shuffleState, repeatValue, currentVolume, artData, favoriteState}
            on error
                return {false, "Not Playing", "Unknown", "Unknown", 0, 0, false, 0, 50, "", false}
            end try
        end tell
        """
        
        return try await AppleScriptHelper.execute(script)
    }
    
}
