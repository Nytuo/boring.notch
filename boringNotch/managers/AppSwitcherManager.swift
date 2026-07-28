//
//  AppSwitcherManager.swift
//  boringNotch
//

import AppKit
import Combine
import Defaults
import SwiftUI

struct RunningApp: Identifiable, Equatable {
    let id: pid_t
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage?
    let isActive: Bool
    let isHidden: Bool

    static func == (lhs: RunningApp, rhs: RunningApp) -> Bool {
        lhs.id == rhs.id && lhs.isActive == rhs.isActive && lhs.isHidden == rhs.isHidden
    }
}

@MainActor
final class AppSwitcherManager: ObservableObject {
    static let shared = AppSwitcherManager()

    @Published private(set) var apps: [RunningApp] = []

    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []

    /// Most-recently-used order, front to back, tracked by activation events.
    /// NSWorkspace does not expose MRU ordering, so we maintain it ourselves.
    private var recentOrder: [pid_t] = []

    private init() {
        Defaults.publisher(.appSwitcherEnabled)
            .sink { [weak self] change in
                Task { @MainActor in
                    if change.newValue {
                        self?.start()
                    } else {
                        self?.stop()
                    }
                }
            }
            .store(in: &cancellables)

        if Defaults[.appSwitcherEnabled] {
            start()
        }
    }

    func start() {
        guard observers.isEmpty else { return }

        let center = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification
        ]

        for name in names {
            let observer = center.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if name == NSWorkspace.didActivateApplicationNotification,
                       let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication {
                        self.noteActivation(of: app.processIdentifier)
                    }
                    self.refresh()
                }
            }
            observers.append(observer)
        }

        seedRecentOrder()
        refresh()
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        apps = []
        recentOrder = []
    }

    // MARK: Ordering

    private func seedRecentOrder() {
        // Best available approximation at startup: the frontmost app first,
        // then everything else in whatever order the system reports.
        let running = Self.switchableApplications()
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        recentOrder = running.map(\.processIdentifier)
        if let frontmost, let index = recentOrder.firstIndex(of: frontmost) {
            recentOrder.remove(at: index)
            recentOrder.insert(frontmost, at: 0)
        }
    }

    private func noteActivation(of pid: pid_t) {
        recentOrder.removeAll { $0 == pid }
        recentOrder.insert(pid, at: 0)
    }

    func refresh() {
        let running = Self.switchableApplications()
        let includeHidden = Defaults[.appSwitcherIncludeMinimized]

        var models = running.compactMap { app -> RunningApp? in
            if !includeHidden && app.isHidden { return nil }
            guard let name = app.localizedName else { return nil }
            return RunningApp(
                id: app.processIdentifier,
                name: name,
                bundleIdentifier: app.bundleIdentifier,
                icon: app.icon,
                isActive: app.isActive,
                isHidden: app.isHidden
            )
        }

        // Sort by the tracked MRU order; anything unseen goes to the end.
        let position = Dictionary(
            uniqueKeysWithValues: recentOrder.enumerated().map { ($0.element, $0.offset) }
        )
        models.sort { lhs, rhs in
            (position[lhs.id] ?? Int.max) < (position[rhs.id] ?? Int.max)
        }

        apps = models
    }

    /// Regular (Dock-visible) applications, excluding this app itself.
    private static func switchableApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
                && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
    }

    // MARK: Actions

    func activate(_ app: RunningApp) {
        guard let running = NSRunningApplication(processIdentifier: app.id) else { return }
        running.unhide()
        running.activate(options: [.activateAllWindows])
        noteActivation(of: app.id)
        refresh()
    }

    func quit(_ app: RunningApp) {
        NSRunningApplication(processIdentifier: app.id)?.terminate()
    }

    func hide(_ app: RunningApp) {
        NSRunningApplication(processIdentifier: app.id)?.hide()
    }
}
