//
//  WindowSnapManager.swift
//  boringNotch
//
//  F-30: keyboard-shortcut-driven window snapping through the XPC helper's
//  `axWindows` capability.
//
//  Scoped down from the plan's drag-to-edge-with-live-preview design to
//  keyboard shortcuts only, snapping the frontmost app's focused window.
//  A drag-to-edge affordance needs a translucent preview overlay tracked
//  against a global mouse monitor in real time — real UI whose correctness
//  is fundamentally a visual question, and there is no way to see it render
//  in this environment. Keyboard-shortcut snapping has no such ambiguity:
//  the target rect is computed from `NSScreen.visibleFrame`, and either the
//  window ends up there or the XPC call fails.
//

import AppKit
import Combine
import Defaults
import Foundation

enum WindowSnapZone: String, CaseIterable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter
    case maximize
    case center

    /// The target frame in Cocoa (bottom-left-origin) screen coordinates,
    /// confined to `visibleFrame` so a snapped window never covers the menu
    /// bar or Dock.
    func cocoaFrame(in visibleFrame: CGRect) -> CGRect {
        let x = visibleFrame.minX
        let y = visibleFrame.minY
        let w = visibleFrame.width
        let h = visibleFrame.height

        switch self {
        case .leftHalf: return CGRect(x: x, y: y, width: w / 2, height: h)
        case .rightHalf: return CGRect(x: x + w / 2, y: y, width: w / 2, height: h)
        case .topHalf: return CGRect(x: x, y: y + h / 2, width: w, height: h / 2)
        case .bottomHalf: return CGRect(x: x, y: y, width: w, height: h / 2)
        case .topLeftQuarter: return CGRect(x: x, y: y + h / 2, width: w / 2, height: h / 2)
        case .topRightQuarter: return CGRect(x: x + w / 2, y: y + h / 2, width: w / 2, height: h / 2)
        case .bottomLeftQuarter: return CGRect(x: x, y: y, width: w / 2, height: h / 2)
        case .bottomRightQuarter: return CGRect(x: x + w / 2, y: y, width: w / 2, height: h / 2)
        case .maximize: return visibleFrame
        case .center:
            let cw = w * 0.6
            let ch = h * 0.8
            return CGRect(x: x + (w - cw) / 2, y: y + (h - ch) / 2, width: cw, height: ch)
        }
    }
}

@MainActor
final class WindowSnapManager {
    static let shared = WindowSnapManager()

    /// One-level undo: the frame the most recent snap overwrote, in Quartz
    /// coordinates (what the helper already speaks) — "restore" re-sends it
    /// unchanged, so there's no coordinate math to redo on the way back.
    private var previousFrame: CGRect?

    private init() {}

    func snap(to zone: WindowSnapZone) {
        guard Defaults[.capabilityAxWindowsEnabled] else { return }
        guard let screen = NSScreen.main else { return }

        let cocoaFrame = zone.cocoaFrame(in: screen.visibleFrame)
        let quartzFrame = Self.quartzFrame(from: cocoaFrame)
        apply(quartzFrame, recordUndo: true)
    }

    func restore() {
        guard Defaults[.capabilityAxWindowsEnabled] else { return }
        guard let frame = previousFrame else { return }
        apply(frame, recordUndo: false)
    }

    private func apply(_ quartzFrame: CGRect, recordUndo: Bool) {
        Task {
            guard let result = await XPCHelperClient.shared.setFocusedWindowFrame(quartzFrame), result.success else { return }
            if recordUndo {
                previousFrame = result.previousFrame
            } else {
                previousFrame = nil
            }
        }
    }

    /// AX/Quartz global display coordinates have their origin at the
    /// top-left of the screen carrying the menu bar (`frame.origin == .zero`
    /// in Cocoa's own system), y increasing downward — not the same screen
    /// `NSScreen.main` necessarily refers to on a multi-monitor setup, and
    /// not the same origin corner as Cocoa's bottom-left/y-up convention
    /// `NSScreen.visibleFrame` uses. Flip against that reference screen's
    /// height, not the target screen's — this is the one calculation in
    /// this feature that's silently correct on every single-monitor setup
    /// even if got wrong, which is exactly why it's called out explicitly
    /// here rather than left to be re-derived.
    private static func quartzFrame(from cocoaFrame: CGRect) -> CGRect {
        let referenceHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height ?? cocoaFrame.maxY
        let quartzY = referenceHeight - cocoaFrame.origin.y - cocoaFrame.height
        return CGRect(x: cocoaFrame.origin.x, y: quartzY, width: cocoaFrame.width, height: cocoaFrame.height)
    }
}
