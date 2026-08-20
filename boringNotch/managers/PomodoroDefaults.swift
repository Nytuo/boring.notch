//
//  PomodoroDefaults.swift
//  boringNotch
//
//  F-13: Pomodoro settings, in their own file per CLAUDE.md — the existing
//  `clock*` keys live in `models/Constants.swift`, which CLAUDE.md itself
//  says is already too big; new keys don't follow that precedent.
//

import Defaults

extension Defaults.Keys {
    static let clockPomodoroWorkMinutes = Key<Int>("clockPomodoroWorkMinutes", default: 25)
    static let clockPomodoroShortBreakMinutes = Key<Int>("clockPomodoroShortBreakMinutes", default: 5)
    static let clockPomodoroLongBreakMinutes = Key<Int>("clockPomodoroLongBreakMinutes", default: 15)
    /// Number of completed work sessions before a long break is taken instead of a short one.
    static let clockPomodoroCyclesBeforeLongBreak = Key<Int>("clockPomodoroCyclesBeforeLongBreak", default: 4)
    /// Whether the next phase starts on its own, or waits for the user to press Start.
    static let clockPomodoroAutoAdvance = Key<Bool>("clockPomodoroAutoAdvance", default: true)
    /// All-time completed work session count, for a minimal session history in settings.
    static let clockPomodoroCompletedSessions = Key<Int>("clockPomodoroCompletedSessions", default: 0)
}
