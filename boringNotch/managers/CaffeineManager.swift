//
//  CaffeineManager.swift
//  boringNotch
//
//  Keeps the Mac awake using IOKit power assertions, in the spirit of
//  Amphetamine / PowerToys Awake.
//

import AppKit
import Combine
import Defaults
import IOKit.pwr_mgt
import SwiftUI

// MARK: - Duration

/// A preset length of time for a caffeine session.
///
/// `.indefinite` holds the assertion until it is explicitly released; every
/// other case expires on its own.
enum CaffeineDuration: Codable, Hashable, Identifiable, Defaults.Serializable {
    case indefinite
    case minutes(Int)

    var id: String {
        switch self {
        case .indefinite: return "indefinite"
        case .minutes(let value): return "minutes-\(value)"
        }
    }

    /// Presets offered in the menu bar and settings.
    static let presets: [CaffeineDuration] = [
        .indefinite,
        .minutes(5),
        .minutes(15),
        .minutes(30),
        .minutes(60),
        .minutes(120),
        .minutes(240),
        .minutes(480)
    ]

    /// Seconds the session should last, or `nil` when it never expires.
    var timeInterval: TimeInterval? {
        switch self {
        case .indefinite: return nil
        case .minutes(let value): return TimeInterval(value * 60)
        }
    }

    var localizedString: String {
        switch self {
        case .indefinite:
            return NSLocalizedString(
                "caffeine_duration_indefinite",
                comment: "Caffeine duration: stays on until turned off"
            )
        case .minutes(let value) where value < 60:
            return String(
                format: NSLocalizedString(
                    "caffeine_duration_minutes",
                    comment: "Caffeine duration in minutes"
                ),
                value
            )
        case .minutes(let value) where value % 60 == 0:
            return String(
                format: NSLocalizedString(
                    "caffeine_duration_hours",
                    comment: "Caffeine duration in whole hours"
                ),
                value / 60
            )
        case .minutes(let value):
            return String(
                format: NSLocalizedString(
                    "caffeine_duration_hours_minutes",
                    comment: "Caffeine duration in hours and minutes"
                ),
                value / 60,
                value % 60
            )
        }
    }
}

// MARK: - Manager

@MainActor
final class CaffeineManager: ObservableObject {
    static let shared = CaffeineManager()

    /// Whether a power assertion is currently held.
    @Published private(set) var isActive: Bool = false

    /// When the current session ends. `nil` while inactive or indefinite.
    @Published private(set) var expiresAt: Date?

    /// Seconds left in the current session, or `nil` when there is no deadline.
    /// Recomputed once a second while a timed session is running.
    @Published private(set) var remaining: TimeInterval?

    /// The duration the active session was started with, kept so the UI can
    /// show what the user picked rather than re-deriving it from the deadline.
    @Published private(set) var activeDuration: CaffeineDuration?

    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var displayAssertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var expiryTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private static let assertionReason = "Boring Notch is keeping this Mac awake"

    private init() {
        // Releasing assertions on terminate is belt-and-braces: the kernel drops
        // them when the process dies, but doing it explicitly keeps `pmset -g
        // assertions` clean during development and fast app relaunches.
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.releaseAssertions()
                }
            }
            .store(in: &cancellables)

        // The display-sleep preference can change mid-session; re-apply so the
        // running session reflects it without needing a manual toggle.
        Defaults.publisher(.caffeineAllowDisplaySleep)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isActive else { return }
                    self.applyAssertions()
                }
            }
            .store(in: &cancellables)

        if Defaults[.caffeineActivateOnLaunch] {
            activate(for: Defaults[.caffeineDefaultDuration])
        }
    }

    // MARK: Public API

    /// Starts (or restarts) a session for `duration`.
    func activate(for duration: CaffeineDuration) {
        expiryTask?.cancel()
        expiryTask = nil

        applyAssertions()

        guard isActive else { return }

        activeDuration = duration

        if let interval = duration.timeInterval {
            let deadline = Date().addingTimeInterval(interval)
            expiresAt = deadline
            remaining = interval
            startCountdown(until: deadline)
        } else {
            expiresAt = nil
            remaining = nil
        }

        announce()
    }

    /// Ends the current session and lets the Mac sleep normally again.
    func deactivate() {
        expiryTask?.cancel()
        expiryTask = nil
        releaseAssertions()
        expiresAt = nil
        remaining = nil
        activeDuration = nil
        announce()
    }

    /// Flashes the state change across the closed notch.
    private func announce() {
        guard Defaults[.caffeineEnabled], Defaults[.caffeineLiveActivity] else { return }
        BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .caffeine)
    }

    /// Turns the current session off, or starts one at the default duration.
    func toggle() {
        if isActive {
            deactivate()
        } else {
            activate(for: Defaults[.caffeineDefaultDuration])
        }
    }

    /// Pushes the deadline of a timed session out by `interval`.
    /// No-op for indefinite sessions, which have no deadline to extend.
    func extend(by interval: TimeInterval) {
        guard isActive, let current = expiresAt else { return }
        let deadline = current.addingTimeInterval(interval)
        expiresAt = deadline
        remaining = deadline.timeIntervalSinceNow
        activeDuration = .minutes(Int(deadline.timeIntervalSince(Date()) / 60))
        startCountdown(until: deadline)
    }

    // MARK: Countdown

    private func startCountdown(until deadline: Date) {
        expiryTask?.cancel()
        expiryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let left = deadline.timeIntervalSinceNow
                if left <= 0 {
                    self.deactivate()
                    return
                }
                self.remaining = left
                // Sleep to the next whole second so the countdown ticks cleanly
                // rather than drifting by the cost of each loop iteration.
                let nextTick = left.truncatingRemainder(dividingBy: 1)
                try? await Task.sleep(for: .seconds(nextTick > 0.01 ? nextTick : 1))
            }
        }
    }

    // MARK: Assertions

    /// Creates the power assertions matching the current preferences, replacing
    /// any already held so a preference change takes effect immediately.
    private func applyAssertions() {
        releaseAssertions()

        var created = false

        // Always prevent idle *system* sleep — that is the core of the feature.
        var id = IOPMAssertionID(0)
        let systemResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            Self.assertionReason as CFString,
            &id
        )
        if systemResult == kIOReturnSuccess {
            assertionID = id
            created = true
        } else {
            NSLog("⚠️ Caffeine: failed to create system sleep assertion (\(systemResult))")
        }

        // Optionally also keep the display lit.
        if !Defaults[.caffeineAllowDisplaySleep] {
            var displayID = IOPMAssertionID(0)
            let displayResult = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                Self.assertionReason as CFString,
                &displayID
            )
            if displayResult == kIOReturnSuccess {
                displayAssertionID = displayID
                created = true
            } else {
                NSLog("⚠️ Caffeine: failed to create display sleep assertion (\(displayResult))")
            }
        }

        isActive = created
    }

    private func releaseAssertions() {
        if assertionID != IOPMAssertionID(0) {
            IOPMAssertionRelease(assertionID)
            assertionID = IOPMAssertionID(0)
        }
        if displayAssertionID != IOPMAssertionID(0) {
            IOPMAssertionRelease(displayAssertionID)
            displayAssertionID = IOPMAssertionID(0)
        }
        isActive = false
    }
}

// MARK: - Formatting

extension CaffeineManager {
    /// `1:23:45` for long sessions, `23:45` otherwise. `nil` when indefinite.
    var formattedRemaining: String? {
        guard let remaining, remaining > 0 else { return nil }
        let total = Int(remaining.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Short status suitable for the menu bar tooltip and notch label.
    var statusText: String {
        guard isActive else {
            return NSLocalizedString("caffeine_status_off", comment: "Caffeine is off")
        }
        if let formattedRemaining {
            return formattedRemaining
        }
        return NSLocalizedString("caffeine_status_on", comment: "Caffeine is on indefinitely")
    }
}
