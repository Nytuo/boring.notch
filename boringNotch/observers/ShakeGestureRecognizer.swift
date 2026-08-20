//
//  ShakeGestureRecognizer.swift
//  boringNotch
//
//  F-10: detects "grab, jiggle, drop" — a drag shaken left-right while in
//  flight — from a stream of mouse positions. Pure gesture math, no event
//  monitors of its own: `DragDetector` already fires `onDragMove`
//  continuously during a content drag, so this is fed from that existing
//  callback rather than registering a second global monitor.
//

import Foundation
import QuartzCore

final class ShakeGestureRecognizer {
    private struct Sample {
        let x: CGFloat
        let time: TimeInterval
    }

    /// How far back a reversal can still count.
    private let windowDuration: TimeInterval = 0.6
    /// Reversals needed inside the window to call it a shake.
    private let requiredReversals = 3
    /// Minimum horizontal travel from the last extreme to count as a
    /// reversal, so hand tremor and slow drift don't trigger it. Divided by
    /// the user's sensitivity setting by the caller.
    var amplitudeThreshold: CGFloat = 40

    /// Suppresses re-triggering on every sample once a shake is detected,
    /// until the gesture is reset (drag ends) or this cools down.
    private let retriggerCooldown: TimeInterval = 1.0
    private var lastTriggerTime: TimeInterval = -.infinity

    private var samples: [Sample] = []

    /// Feeds one position sample. Returns `true` the instant a shake is
    /// recognized (fires at most once per `retriggerCooldown`).
    @discardableResult
    func recordPosition(_ point: CGPoint) -> Bool {
        let now = CACurrentMediaTime()
        samples.append(Sample(x: point.x, time: now))
        samples.removeAll { now - $0.time > windowDuration }

        guard now - lastTriggerTime > retriggerCooldown else { return false }
        guard countReversals() >= requiredReversals else { return false }

        lastTriggerTime = now
        return true
    }

    func reset() {
        samples.removeAll()
    }

    /// Counts amplitude-filtered direction changes: walks the samples,
    /// tracking the last local extreme, and counts a reversal each time
    /// movement away from it exceeds `amplitudeThreshold` in the opposite
    /// direction from the current run.
    private func countReversals() -> Int {
        guard let first = samples.first else { return 0 }

        var reversals = 0
        var direction = 0
        var extremeX = first.x

        for sample in samples.dropFirst() {
            let delta = sample.x - extremeX
            guard abs(delta) >= amplitudeThreshold else { continue }

            let newDirection = delta > 0 ? 1 : -1
            if direction != 0 && newDirection != direction {
                reversals += 1
            }
            direction = newDirection
            extremeX = sample.x
        }

        return reversals
    }
}
