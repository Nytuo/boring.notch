//
//  CatcherPresenter.swift
//  boringNotch
//
//  F-10: springs the notch open to the shelf when a drag is shaken, and
//  auto-closes it again a couple of seconds after the drag ends. Reuses the
//  same open-to-shelf path `DragDetector.onDragEntersNotchRegion` already
//  drives (`AppDelegate.handleDragEntersNotchRegion`) — the shelf itself is
//  already a drop target once open, so there is nothing new to register.
//

import AppKit
import Defaults

@MainActor
final class CatcherPresenter {
    private let recognizer = ShakeGestureRecognizer()
    private var closeTask: Task<Void, Never>?
    private var caughtScreen: NSScreen?

    /// Called the instant a shake is detected on `screen`.
    var onCatch: ((NSScreen) -> Void)?
    /// Called after the auto-close delay following a drag that triggered a
    /// catch. The caller decides whether closing still makes sense (e.g. the
    /// user may have switched tabs or pinned the shelf open since).
    var onAutoClose: ((NSScreen) -> Void)?

    /// Feed every `DragDetector.onDragMove` sample here.
    func recordDragPosition(_ point: CGPoint, on screen: NSScreen) {
        guard Defaults[.catcherEnabled] else { return }

        recognizer.amplitudeThreshold = Self.baseAmplitude / max(0.25, Defaults[.catcherSensitivity])

        guard recognizer.recordPosition(point) else { return }

        closeTask?.cancel()
        closeTask = nil
        caughtScreen = screen
        onCatch?(screen)
    }

    /// Call from `DragDetector.onDragEnd` (drop or cancel — the detector
    /// cannot tell the two apart, so both auto-close the same way).
    func dragDidEnd() {
        recognizer.reset()
        guard let screen = caughtScreen else { return }
        caughtScreen = nil

        closeTask?.cancel()
        let delay = Defaults[.catcherAutoCloseDelay]
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.onAutoClose?(screen)
        }
    }

    /// Amplitude threshold in points at the default (1.0) sensitivity,
    /// matching the plan's ">40 pt" spec.
    static let baseAmplitude: CGFloat = 40
}
