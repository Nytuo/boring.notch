//
//  PomodoroManager.swift
//  boringNotch
//
//  F-13: a work/break cycle layered on top of `ClockManager`'s existing
//  countdown — no new timing engine, per the plan. Drives the same
//  `timerEndDate`/`timerDuration` machinery `TimerFaceView` already uses, so
//  the closed-notch reading (`ClockClosedIndicator`) picks up a running
//  Pomodoro phase for free, as an ordinary running timer.
//
//  Only reacts to `ClockManager.timerDidFinish` while a cycle is active
//  (`isCycleActive`), so using the plain Timer face is completely unaffected.
//

import Combine
import Defaults
import Foundation

enum PomodoroPhase {
    case work
    case shortBreak
    case longBreak

    var label: String {
        switch self {
        case .work: return NSLocalizedString("pomodoro_phase_work", comment: "Pomodoro phase: work")
        case .shortBreak: return NSLocalizedString("pomodoro_phase_short_break", comment: "Pomodoro phase: short break")
        case .longBreak: return NSLocalizedString("pomodoro_phase_long_break", comment: "Pomodoro phase: long break")
        }
    }

    var iconName: String {
        switch self {
        case .work: return "brain.head.profile"
        case .shortBreak: return "cup.and.saucer"
        case .longBreak: return "figure.walk"
        }
    }
}

@MainActor
final class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    @Published private(set) var isCycleActive = false
    @Published private(set) var phase: PomodoroPhase = .work
    /// Work sessions completed since the cycle was started, for the
    /// long-break cadence. Resets when the cycle stops.
    @Published private(set) var completedWorkSessions = 0

    private let clock = ClockManager.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {
        clock.$timerDidFinish
            .sink { [weak self] finished in
                guard finished, let self, self.isCycleActive else { return }
                self.advance()
            }
            .store(in: &cancellables)
    }

    /// Starts a fresh cycle from the work phase.
    func startCycle() {
        guard !isCycleActive else { return }
        isCycleActive = true
        phase = .work
        completedWorkSessions = 0
        beginPhase()
    }

    func stopCycle() {
        guard isCycleActive else { return }
        isCycleActive = false
        clock.resetTimer()
    }

    /// Starts the current phase's countdown when it is set up but waiting
    /// (either `clockPomodoroAutoAdvance` is off, or the phase was paused).
    func startCurrentPhase() {
        guard isCycleActive else { return }
        clock.startTimer()
    }

    func pauseCurrentPhase() {
        guard isCycleActive else { return }
        clock.pauseTimer()
    }

    /// Ends the current phase early and moves to the next one, same as it
    /// finishing on its own.
    func skipPhase() {
        guard isCycleActive else { return }
        advance()
    }

    private func advance() {
        if phase == .work {
            completedWorkSessions += 1
            Defaults[.clockPomodoroCompletedSessions] += 1
            let cyclesBeforeLongBreak = max(1, Defaults[.clockPomodoroCyclesBeforeLongBreak])
            phase = completedWorkSessions.isMultiple(of: cyclesBeforeLongBreak) ? .longBreak : .shortBreak
        } else {
            phase = .work
        }

        if Defaults[.clockPomodoroAutoAdvance] {
            beginPhase()
        } else {
            clock.resetTimer()
            clock.setTimerDuration(durationForCurrentPhase)
        }
    }

    private func beginPhase() {
        clock.resetTimer()
        clock.setTimerDuration(durationForCurrentPhase)
        clock.startTimer()
    }

    private var durationForCurrentPhase: TimeInterval {
        switch phase {
        case .work:
            return TimeInterval(max(1, Defaults[.clockPomodoroWorkMinutes]) * 60)
        case .shortBreak:
            return TimeInterval(max(1, Defaults[.clockPomodoroShortBreakMinutes]) * 60)
        case .longBreak:
            return TimeInterval(max(1, Defaults[.clockPomodoroLongBreakMinutes]) * 60)
        }
    }
}
