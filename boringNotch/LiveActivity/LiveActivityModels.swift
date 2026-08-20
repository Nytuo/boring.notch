//
//  LiveActivityModels.swift
//  boringNotch
//
//  F-03: the closed notch has one slot and many claimants — music, battery,
//  downloads, Bluetooth, notifications, caffeine, clock, system stats, and
//  everything Phase 2+ adds (VPN, agent progress, meeting controls...). Today
//  arbitration is a hand-written `if/else if` ladder inside
//  `ContentView.computedChinWidth`, plus two more ad-hoc paths
//  (`BoringViewCoordinator.expandingView`, and static `Closed*Indicator.isActive`
//  checks for clock/system stats) — three mechanisms, no shared priority rule.
//
//  This file is the vocabulary for a fourth, unified mechanism
//  (`LiveActivityCenter`) that replaces all three. It does not yet: see
//  `LiveActivityCenter.swift` for why the migration is staged.
//

import SwiftUI

enum LiveActivityPriority: Int, Comparable {
    /// Decoration with no event behind it — always true, so anything with an
    /// actual event wins. (System stats, the "not human face" idle state.)
    case ambient = 0
    /// A steady-state reading worth showing when nothing more urgent is
    /// happening. (Clock/timer countdown, Keep Awake countdown, music.)
    case informational = 1
    /// A time-boxed event the user should notice but that resolves on its
    /// own. (Download in progress, screenshot preview, Bluetooth connect.)
    case transient = 2
    /// Something the user very likely needs to see right now. (Battery
    /// power-source change, low-battery warning, an active notification.)
    case urgent = 3

    static func < (lhs: LiveActivityPriority, rhs: LiveActivityPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum LiveActivityLifetime {
    /// Stays claimed until explicitly withdrawn (a running timer, an active
    /// VPN connection, Caffeine). Sticky claimants reappear once every
    /// transient ahead of them expires.
    case sticky
    /// Auto-withdraws after the given duration if not resubmitted first.
    case timed(TimeInterval)
}

/// One claimant's bid for the closed-notch slot. Resubmitting the same `id`
/// replaces the previous bid in place rather than queueing a duplicate.
struct LiveActivity: Identifiable {
    /// Stable per-claimant identifier, e.g. `"clock.timer"`, `"music.playback"`.
    /// Two claimants must never share an id; one claimant resubmitting the
    /// same id is how it updates its own content.
    let id: String
    /// The extension manifest id that owns this claim, for debugging/logging.
    let owner: String
    var priority: LiveActivityPriority
    var lifetime: LiveActivityLifetime
    var leading: AnyView
    var trailing: AnyView
    var expanded: AnyView?
    var onTap: (() -> Void)?
}

/// The documented priority table this plan section requires (F-03
/// acceptance criterion). Extracted from the precedence already implicit in
/// `ContentView.computedChinWidth`'s if/else ladder as of this writing:
///
/// 1. `.urgent`        — battery power-source change, active notification banner
/// 2. `.transient`      — Keep Awake countdown banner, Bluetooth connect, download
///                        banner, screenshot banner, lock-screen widgets
/// 3. `.informational`  — music now-playing, download-in-progress indicator,
///                        clock/timer countdown, Keep Awake notch countdown
/// 4. `.ambient`        — system stats indicator, idle decoration
///
/// Within a priority tier, the most recently submitted claimant wins. When a
/// tier empties (its claimant withdraws or a `.timed` lifetime expires), the
/// highest remaining `.sticky` claimant reappears — it was never displaced,
/// only covered.
enum LiveActivityPriorityTable {}
