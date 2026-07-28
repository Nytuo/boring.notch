//
//  ClockManager.swift
//  boringNotch
//
//  State behind the clock tab: a countdown timer and a stopwatch that keep
//  running while the notch is closed.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

/// Which face the clock tab is showing.
enum ClockMode: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case clock
    case timer
    case stopwatch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clock: return NSLocalizedString("clock_mode_clock", comment: "Clock tab mode: clock")
        case .timer: return NSLocalizedString("clock_mode_timer", comment: "Clock tab mode: timer")
        case .stopwatch: return NSLocalizedString("clock_mode_stopwatch", comment: "Clock tab mode: stopwatch")
        }
    }

    var iconName: String {
        switch self {
        case .clock: return "clock"
        case .timer: return "timer"
        case .stopwatch: return "stopwatch"
        }
    }
}

/// Both the timer and the stopwatch are stored as a start date plus whatever
/// had already accumulated, rather than a tick count. Nothing then depends on a
/// ticker actually firing: the views read the elapsed time from the clock when
/// they draw, so a closed notch, a sleeping display or a dropped frame cannot
/// make the numbers drift.
@MainActor
final class ClockManager: ObservableObject {
    static let shared = ClockManager()

    // MARK: Timer

    /// Total length of the current countdown.
    @Published private(set) var timerDuration: TimeInterval
    /// When the countdown is due to hit zero, while it is running.
    @Published private(set) var timerEndDate: Date?
    /// Time left on a paused countdown.
    @Published private(set) var timerPausedRemaining: TimeInterval?
    /// Set when a countdown reaches zero, cleared as soon as it is reset.
    @Published private(set) var timerDidFinish = false

    private var timerCompletionTask: Task<Void, Never>?

    var isTimerRunning: Bool { timerEndDate != nil }
    var isTimerActive: Bool { isTimerRunning || timerPausedRemaining != nil }

    /// Seconds left right now. Reads the clock rather than a stored countdown,
    /// so it stays correct however long the view was off screen.
    var timerRemaining: TimeInterval {
        if let endDate = timerEndDate {
            return max(0, endDate.timeIntervalSinceNow)
        }
        return timerPausedRemaining ?? timerDuration
    }

    var timerProgress: Double {
        guard timerDuration > 0 else { return 0 }
        return min(1, max(0, 1 - timerRemaining / timerDuration))
    }

    // MARK: Stopwatch

    /// When the current run started, while the stopwatch is running.
    @Published private(set) var stopwatchStartedAt: Date?
    /// Time banked by previous runs, so pause/resume adds up.
    @Published private(set) var stopwatchAccumulated: TimeInterval = 0
    @Published private(set) var laps: [TimeInterval] = []

    var isStopwatchRunning: Bool { stopwatchStartedAt != nil }
    var isStopwatchActive: Bool { isStopwatchRunning || stopwatchAccumulated > 0 }

    var stopwatchElapsed: TimeInterval {
        guard let startedAt = stopwatchStartedAt else { return stopwatchAccumulated }
        return stopwatchAccumulated - startedAt.timeIntervalSinceNow
    }

    private var cancellables = Set<AnyCancellable>()

    private init() {
        timerDuration = TimeInterval(max(1, Defaults[.clockDefaultTimerMinutes]) * 60)

        // Follow the configured default while nothing is counting: otherwise
        // changing it in settings would not show up until the next launch.
        Defaults.publisher(.clockDefaultTimerMinutes)
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self, !self.isTimerActive, !self.timerDidFinish else { return }
                    self.timerDuration = TimeInterval(max(1, change.newValue) * 60)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Timer control

    /// Sets the countdown length. Ignored while one is running, so a stray
    /// click on a preset cannot silently restart a countdown in progress.
    func setTimerDuration(_ duration: TimeInterval) {
        guard !isTimerRunning else { return }
        timerDuration = max(1, duration.rounded())
        timerPausedRemaining = nil
        timerDidFinish = false
    }

    func adjustTimerDuration(by delta: TimeInterval) {
        if isTimerRunning, let endDate = timerEndDate {
            // Extending or trimming a running countdown moves its end date and
            // its total together, so the progress ring stays honest.
            let newRemaining = max(1, endDate.timeIntervalSinceNow + delta)
            timerDuration = max(1, timerDuration + delta)
            timerEndDate = Date().addingTimeInterval(newRemaining)
            scheduleTimerCompletion()
        } else {
            setTimerDuration(timerRemaining + delta)
        }
    }

    func startTimer() {
        let remaining = timerPausedRemaining ?? timerDuration
        guard remaining > 0 else { return }

        timerDidFinish = false
        timerPausedRemaining = nil
        timerEndDate = Date().addingTimeInterval(remaining)
        scheduleTimerCompletion()
    }

    func pauseTimer() {
        guard let endDate = timerEndDate else { return }
        timerCompletionTask?.cancel()
        timerCompletionTask = nil
        timerPausedRemaining = max(0, endDate.timeIntervalSinceNow)
        timerEndDate = nil
    }

    func toggleTimer() {
        isTimerRunning ? pauseTimer() : startTimer()
    }

    func resetTimer() {
        timerCompletionTask?.cancel()
        timerCompletionTask = nil
        timerEndDate = nil
        timerPausedRemaining = nil
        timerDidFinish = false
    }

    private func scheduleTimerCompletion() {
        timerCompletionTask?.cancel()
        guard let endDate = timerEndDate else { return }

        timerCompletionTask = Task { @MainActor [weak self] in
            let delay = max(0, endDate.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            // A pause or reset in the meantime replaces the end date, so only
            // fire for the countdown this task was scheduled for.
            guard self.timerEndDate == endDate else { return }
            self.finishTimer()
        }
    }

    private func finishTimer() {
        timerEndDate = nil
        timerPausedRemaining = nil
        timerDidFinish = true

        if Defaults[.clockTimerSound] {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
        // Nothing to show if the feature has been switched off since the
        // countdown started.
        if Defaults[.clockTimerOpensNotch] && Defaults[.clockEnabled] {
            NotificationCenter.default.post(name: .clockTimerFinished, object: nil)
        }
    }

    // MARK: Stopwatch control

    func startStopwatch() {
        guard stopwatchStartedAt == nil else { return }
        stopwatchStartedAt = Date()
    }

    func pauseStopwatch() {
        guard let startedAt = stopwatchStartedAt else { return }
        stopwatchAccumulated -= startedAt.timeIntervalSinceNow
        stopwatchStartedAt = nil
    }

    func toggleStopwatch() {
        isStopwatchRunning ? pauseStopwatch() : startStopwatch()
    }

    func resetStopwatch() {
        stopwatchStartedAt = nil
        stopwatchAccumulated = 0
        laps.removeAll()
    }

    /// Records a lap, newest first.
    func recordLap() {
        guard isStopwatchRunning else { return }
        laps.insert(stopwatchElapsed, at: 0)
    }

    // MARK: Formatting

    /// `m:ss` under an hour, `h:mm:ss` above it.
    static func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Same, plus hundredths — for the stopwatch, where they are the point.
    static func formatPreciseDuration(_ interval: TimeInterval) -> String {
        let clamped = max(0, interval)
        let hundredths = Int((clamped * 100).rounded(.down)) % 100
        return String(format: "%@.%02d", formatDuration(clamped.rounded(.down)), hundredths)
    }
}
