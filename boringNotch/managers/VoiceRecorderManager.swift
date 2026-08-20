//
//  VoiceRecorderManager.swift
//  boringNotch
//
//  F-40: voice notes with on-device transcription.
//
//  `AudioCaptureManager` doesn't help here despite the name — it taps a
//  music app's *output* via a Core Audio process tap for the waveform
//  visualizer, not microphone *input*. Voice notes need a genuinely
//  different capture path (`AVAudioRecorder` on the input device), so this
//  is a new manager rather than an extension of that one.
//

import AVFoundation
import Defaults
import Foundation
import Speech

@MainActor
final class VoiceRecorderManager: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = VoiceRecorderManager()

    @Published private(set) var isRecording = false
    @Published private(set) var elapsedTime: TimeInterval = 0
    /// 0...1, from `AVAudioRecorder`'s metering — for a live waveform view.
    @Published private(set) var waveformLevel: Float = 0
    @Published private(set) var isTranscribing = false

    private var recorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var startDate: Date?

    private override init() {
        super.init()
    }

    var isAvailable: Bool { Defaults[.voiceRecorderEnabled] }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    func startRecording() {
        guard isAvailable, !isRecording else { return }
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else { return }
            beginRecordingSession()
        }
    }

    private func beginRecordingSession() {
        guard let url = Self.newRecordingURL() else { return }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record() else { return }

            self.recorder = recorder
            self.startDate = Date()
            self.isRecording = true
            self.elapsedTime = 0
            self.waveformLevel = 0
            startLevelTimer()
            BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .voiceRecording)
        } catch {
            NSLog("⚠️ VoiceRecorder: could not start recording: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        guard isRecording, let recorder else { return }

        let url = recorder.url
        recorder.stop()
        self.recorder = nil
        isRecording = false
        levelTimer?.invalidate()
        levelTimer = nil

        addToShelf(url, isTemporary: false)

        if Defaults[.voiceRecorderAutoTranscribe] {
            transcribe(url)
        }
    }

    private func startLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateLevel() }
        }
    }

    private func updateLevel() {
        guard let recorder, isRecording else { return }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        // Typical mic dB range is roughly -60...0; map to 0...1.
        let normalized = pow(10, db / 20)
        waveformLevel = min(1, max(0, normalized))
        elapsedTime = Date().timeIntervalSince(startDate ?? Date())
    }

    // MARK: - Transcription

    /// On-device only (`requiresOnDeviceRecognition = true`) — audio and
    /// transcript never leave the machine, matching the Info.plist
    /// disclosure and CLAUDE.md's privacy rules.
    func transcribe(_ url: URL) {
        guard !isTranscribing else { return }
        isTranscribing = true
        Task {
            let transcript = await Self.performTranscription(url: url)
            self.isTranscribing = false
            if let transcript, !transcript.isEmpty {
                self.saveTranscriptSidecar(transcript, for: url)
            }
        }
    }

    private static func performTranscription(url: URL) async -> String? {
        let authorized: Bool
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            authorized = true
        case .notDetermined:
            authorized = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            authorized = false
        }
        guard authorized else { return nil }

        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { return nil }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        return await withCheckedContinuation { continuation in
            var didResume = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !didResume else { return }
                if let result, result.isFinal {
                    didResume = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if error != nil {
                    didResume = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func saveTranscriptSidecar(_ transcript: String, for audioURL: URL) {
        let sidecarURL = audioURL.deletingPathExtension().appendingPathExtension("txt")
        try? transcript.write(to: sidecarURL, atomically: true, encoding: .utf8)
        addToShelf(sidecarURL, isTemporary: false)
    }

    // MARK: - Storage

    private static func newRecordingURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("VoiceNotes", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = "Voice Note \(formatter.string(from: Date())).m4a"
        return dir.appendingPathComponent(name)
    }

    private func addToShelf(_ url: URL, isTemporary: Bool) {
        guard let bookmark = try? Bookmark(url: url) else { return }
        let item = ShelfItem(kind: .file(bookmark: bookmark.data), isTemporary: isTemporary)
        ShelfStateViewModel.shared.add([item])
    }
}
