//
//  LiveActivityCenter.swift
//  boringNotch
//
//  F-03: the arbitration engine. `current` always holds the highest-priority
//  live claimant, computed deterministically from `submit`/`withdraw` calls —
//  see `LiveActivityModels.swift` for the priority table and lifetime rules.
//
//  Scope of this pass: this ships the engine and the documented priority
//  table, gated fully off by `Defaults[.useActivityBusV2]` (default false).
//  It does not yet replace `ContentView.computedChinWidth`'s if/else ladder,
//  `BoringViewCoordinator.expandingView`, or the `Closed*Indicator.isActive`
//  static checks — that rendering path is hand-tuned against real hardware
//  (physical notch height, multi-display, OSD overlays) and migrating it
//  blind, without a way to visually verify the result here, is exactly the
//  kind of change the plan's own rollout note warns against: "Migrate
//  producers one at a time behind Defaults[.useActivityBusV2], keeping the
//  old path for one release." This lands the bus first so F-22/F-25 (VPN
//  status, AI agent progress) — the next two claimants the plan calls out —
//  can be built as `LiveActivityCenter` producers from day one instead of
//  extending the ladder further. Wiring `ContentView` to read from the bus
//  when the flag is on is follow-up work, tracked as the natural next step
//  once there's a way to verify closed-notch rendering visually.
//

import Combine
import Defaults
import SwiftUI

extension Defaults.Keys {
    /// Off by default: current behavior (the `computedChinWidth` ladder) is
    /// completely unaffected until this flips and `ContentView` is migrated
    /// to read from `LiveActivityCenter` instead.
    static let useActivityBusV2 = Key<Bool>("useActivityBusV2", default: false)
}

@MainActor
final class LiveActivityCenter: ObservableObject {
    static let shared = LiveActivityCenter()

    /// The claimant that should currently hold the closed-notch slot, or
    /// `nil` when nothing has claimed it.
    @Published private(set) var current: LiveActivity?

    private var claims: [String: LiveActivity] = [:]
    /// Submission order, for the "most recent wins" same-priority tiebreak —
    /// dictionary iteration order is not insertion order, so this is tracked
    /// explicitly rather than relied on.
    private var submissionSequence: [String: Int] = [:]
    private var nextSequence = 0
    private var expiryTasks: [String: Task<Void, Never>] = [:]

    private init() {}

    /// Submits or replaces a claimant's bid. Resolves `current` immediately.
    func submit(_ activity: LiveActivity) {
        claims[activity.id] = activity
        nextSequence += 1
        submissionSequence[activity.id] = nextSequence
        expiryTasks[activity.id]?.cancel()

        if case .timed(let duration) = activity.lifetime {
            expiryTasks[activity.id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled else { return }
                self?.withdraw(activity.id)
            }
        }

        recompute()
    }

    /// Withdraws a claimant. If it was showing, the next-highest-priority
    /// claimant takes over, or `current` clears if none remain.
    func withdraw(_ id: String) {
        guard claims.removeValue(forKey: id) != nil else { return }
        submissionSequence[id] = nil
        expiryTasks[id]?.cancel()
        expiryTasks[id] = nil
        recompute()
    }

    private func recompute() {
        current = claims.values.max { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return (submissionSequence[lhs.id] ?? 0) < (submissionSequence[rhs.id] ?? 0)
        }
    }
}
