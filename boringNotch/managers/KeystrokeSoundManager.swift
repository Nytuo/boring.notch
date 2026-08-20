//
//  KeystrokeSoundManager.swift
//  boringNotch
//
//  F-32: this is the highest-privacy-sensitivity feature in the app — the
//  helper installs a system-wide, listen-only key-down tap. The design
//  constraint that makes it defensible: the helper never sends this app a
//  key code, only a 0-11 "pitch bucket" derived from `keyCode % 12` inside
//  the tap callback itself (`BoringNotchXPCHelper.startKeystrokeObserver`).
//  This app receives and plays that bucket and nothing else — there is no
//  code path here, or in the helper, that logs, stores, or transmits which
//  key was pressed. Off by default; enabling it flips the `input` capability
//  and shows the disclosure below before the Input Monitoring TCC prompt.
//
//  Click sounds are synthesized (short decaying sine tones), not sampled —
//  avoids sourcing/licensing audio for a feature with no bundled assets to
//  build on (see the F-9 sprint's investigation).
//

import AVFoundation
import Combine
import Defaults
import Foundation

@MainActor
final class KeystrokeSoundManager: NSObject, ObservableObject, KeystrokeEventReceiver {
    static let shared = KeystrokeSoundManager()

    @Published private(set) var isActive = false

    private var engine: AVAudioEngine?
    private var playerNodes: [AVAudioPlayerNode] = []
    private var clickBuffers: [AVAudioPCMBuffer] = []
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
        Defaults.publisher(keys: .keystrokeSoundsEnabled, .capabilityInputEnabled)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            .store(in: &cancellables)
        Defaults.publisher(.keystrokeSoundsExcludedApps)
            .sink { [weak self] change in
                Task { self?.pushExcludedApps(change.newValue) }
            }
            .store(in: &cancellables)
        refresh()
    }

    nonisolated private func pushExcludedApps(_ bundleIDs: [String]) {
        Task {
            await XPCHelperClient.shared.setKeystrokeExcludedApps(bundleIDs)
        }
    }

    private func refresh() {
        let shouldRun = Defaults[.keystrokeSoundsEnabled] && Defaults[.capabilityInputEnabled]
        shouldRun ? start() : stop()
    }

    private func start() {
        guard !isActive else { return }
        setUpAudioEngine()
        Task {
            let started = await XPCHelperClient.shared.startKeystrokeObserver(receiver: self)
            guard started else {
                await MainActor.run { self.tearDownAudioEngine() }
                return
            }
            await XPCHelperClient.shared.setKeystrokeExcludedApps(Defaults[.keystrokeSoundsExcludedApps])
            self.isActive = true
        }
    }

    private func stop() {
        guard isActive else { return }
        isActive = false
        Task { await XPCHelperClient.shared.stopKeystrokeObserver() }
        tearDownAudioEngine()
    }

    nonisolated func keystrokeDidOccur(pitchIndex: Int) {
        Task { @MainActor in
            self.playClick(pitchIndex: pitchIndex)
        }
    }

    private func playClick(pitchIndex: Int) {
        guard isActive, !playerNodes.isEmpty else { return }
        let index = ((pitchIndex % playerNodes.count) + playerNodes.count) % playerNodes.count
        let node = playerNodes[index]
        let buffer = clickBuffers[index]

        node.stop()
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        node.volume = Float(Defaults[.keystrokeSoundsVolume])
        node.play()
    }

    // MARK: - Audio engine

    private func setUpAudioEngine() {
        guard engine == nil else { return }

        let engine = AVAudioEngine()
        let format = engine.mainMixerNode.outputFormat(forBus: 0)

        var nodes: [AVAudioPlayerNode] = []
        var buffers: [AVAudioPCMBuffer] = []
        for pitchIndex in 0..<12 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            nodes.append(node)
            buffers.append(Self.synthesizeClick(pitchIndex: pitchIndex, format: format))
        }

        do {
            try engine.start()
        } catch {
            NSLog("⚠️ KeystrokeSoundManager: could not start audio engine: \(error.localizedDescription)")
            return
        }

        self.engine = engine
        self.playerNodes = nodes
        self.clickBuffers = buffers
    }

    private func tearDownAudioEngine() {
        engine?.stop()
        engine = nil
        playerNodes = []
        clickBuffers = []
    }

    /// A short, decaying sine blip — click-like without sampling anything.
    /// Frequency rises slightly with `pitchIndex` for the "per-key pitch
    /// variation" the plan asks for, using only the harmless 0-11 bucket
    /// this feature ever sees.
    private static func synthesizeClick(pitchIndex: Int, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let duration = 0.035
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) ?? AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        buffer.frameLength = buffer.frameCapacity

        let frequency = 550.0 + Double(pitchIndex) * 35.0
        guard let channelData = buffer.floatChannelData else { return buffer }

        for frame in 0..<Int(buffer.frameLength) {
            let t = Double(frame) / sampleRate
            let envelope = exp(-t * 90)
            let sample = Float(sin(2 * .pi * frequency * t) * envelope * 0.18)
            for channel in 0..<Int(format.channelCount) {
                channelData[channel][frame] = sample
            }
        }

        return buffer
    }
}
