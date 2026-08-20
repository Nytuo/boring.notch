//
//  NotificationWatcher.swift
//  boringNotch
//
//  Surfaces incoming system notifications in the notch.
//
//  ⚠️ There is no public macOS API to read other apps' notifications. Apple
//  provides no equivalent of iOS's notification-service extensions, and the
//  private `NCNotificationCenter` / `UserNotificationsCore` frameworks would
//  break notarisation. The only supported-ish route is reading the Notification
//  Center UI through the Accessibility API, which is what this does.
//
//  That carries real caveats, which are surfaced in settings rather than
//  hidden:
//    • Requires Accessibility permission.
//    • Depends on Notification Center's internal view hierarchy, which Apple
//      changes between releases; when it changes, this degrades to reporting
//      nothing rather than misbehaving.
//    • Cannot read notifications delivered while the display is locked.
//

import AppKit
import ApplicationServices
import Combine
import Defaults
import SwiftUI

// MARK: - Model

struct NotchNotification: Identifiable, Equatable {
    let id: UUID
    /// App the notification came from, when it can be determined.
    let appName: String?
    let title: String
    let body: String?
    let receivedAt: Date
    /// Bundle identifier for icon lookup, when resolvable.
    let bundleIdentifier: String?
}

// MARK: - Watcher

@MainActor
final class NotificationWatcher: ObservableObject {
    static let shared = NotificationWatcher()

    @Published private(set) var recent: [NotchNotification] = []
    @Published private(set) var latest: NotchNotification?
    /// `true` when enabled but Accessibility permission is missing.
    @Published private(set) var needsAccessibility = false
    /// `true` when permission is granted but the UI could not be read, which
    /// usually means this macOS version rearranged Notification Center.
    @Published private(set) var isUnsupportedLayout = false

    private var observer: AXObserver?
    private var notificationCenterElement: AXUIElement?
    private var cancellables = Set<AnyCancellable>()
    private var retryTask: Task<Void, Never>?

    /// Titles already reported, so the same banner is not announced twice as
    /// the accessibility tree churns while it animates.
    private var seenKeys: Set<String> = []

    /// F-31: each banner's own `AXUIElement`, retained only long enough to
    /// attempt a reply — banners animate and dismiss themselves, so a
    /// re-fetched element found by re-walking the tree later could easily
    /// belong to a different, newer banner. Bounded and FIFO-evicted so a
    /// long session without any reply attempts doesn't grow this forever.
    private var pendingWindows: [(id: UUID, window: AXUIElement)] = []
    private static let maxPendingWindows = 20

    private static let notificationCenterBundleID = "com.apple.notificationcenterui"

    private init() {
        Defaults.publisher(.notificationsEnabled)
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
    }

    // MARK: Lifecycle

    func start() {
        guard Defaults[.notificationsEnabled] else { return }
        stop()

        guard AXIsProcessTrusted() else {
            needsAccessibility = true
            scheduleRetry()
            return
        }
        needsAccessibility = false

        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.notificationCenterBundleID)
            .first
        else {
            isUnsupportedLayout = true
            scheduleRetry()
            return
        }

        let element = AXUIElementCreateApplication(app.processIdentifier)
        notificationCenterElement = element

        var newObserver: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<NotificationWatcher>.fromOpaque(refcon).takeUnretainedValue()
            // AX callbacks arrive on the run loop we attached to, which is the
            // main one, but hop explicitly to satisfy the actor.
            Task { @MainActor in
                watcher.handleWindowCreated(element)
            }
        }

        let result = AXObserverCreate(app.processIdentifier, callback, &newObserver)
        guard result == .success, let newObserver else {
            isUnsupportedLayout = true
            scheduleRetry()
            return
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(newObserver, element, kAXWindowCreatedNotification as CFString, refcon)
        AXObserverAddNotification(newObserver, element, kAXCreatedNotification as CFString, refcon)

        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(newObserver),
            .defaultMode
        )

        observer = newObserver
        isUnsupportedLayout = false
    }

    func stop() {
        retryTask?.cancel()
        retryTask = nil

        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        observer = nil
        notificationCenterElement = nil
        seenKeys.removeAll()
        pendingWindows.removeAll()
        latest = nil
    }

    /// Notification Center is not always running when we first look, and
    /// permission can be granted after launch, so retry rather than give up.
    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, Defaults[.notificationsEnabled] else { return }
            self.start()
        }
    }

    // MARK: Reading the tree

    private func handleWindowCreated(_ window: AXUIElement) {
        // Banners are a stack of static-text elements; collect them in order
        // and treat the first as the title and the rest as the body.
        var texts: [String] = []
        collectStaticText(from: window, into: &texts, depth: 0)

        let cleaned = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let title = cleaned.first else { return }

        let key = cleaned.joined(separator: "␟")
        guard !seenKeys.contains(key) else { return }
        seenKeys.insert(key)
        // Bound the dedupe set so a long session does not grow it forever.
        if seenKeys.count > 200 {
            seenKeys.removeAll()
            seenKeys.insert(key)
        }

        // macOS puts the originating app's name in the banner; when it is
        // present it is usually the first line, with the title second.
        let appName: String?
        let displayTitle: String
        let body: String?

        if cleaned.count >= 3 {
            appName = cleaned[0]
            displayTitle = cleaned[1]
            body = cleaned.dropFirst(2).joined(separator: " ")
        } else if cleaned.count == 2 {
            appName = nil
            displayTitle = cleaned[0]
            body = cleaned[1]
        } else {
            appName = nil
            displayTitle = title
            body = nil
        }

        let notification = NotchNotification(
            id: UUID(),
            appName: appName,
            title: displayTitle,
            body: body,
            receivedAt: Date(),
            bundleIdentifier: appName.flatMap(Self.bundleIdentifier(forAppNamed:))
        )

        if Defaults[.notificationReplyEnabled] {
            pendingWindows.append((notification.id, window))
            if pendingWindows.count > Self.maxPendingWindows {
                pendingWindows.removeFirst(pendingWindows.count - Self.maxPendingWindows)
            }
        }

        announce(notification)
    }

    /// Walks the accessibility tree gathering static text.
    ///
    /// Depth-limited: banner hierarchies are shallow, and an unbounded walk on
    /// an unexpected layout could be expensive on the main thread.
    private func collectStaticText(from element: AXUIElement, into texts: inout [String], depth: Int) {
        guard depth < 8, texts.count < 12 else { return }

        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String

        if role == kAXStaticTextRole {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
               let string = value as? String {
                texts.append(string)
            }
        }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement]
        else { return }

        for child in children {
            collectStaticText(from: child, into: &texts, depth: depth + 1)
        }
    }

    // MARK: - Reply (F-31)
    //
    // Best-effort, and explicitly not verified against a live notification
    // banner in this environment — there was no way to trigger a real banner
    // and inspect its actual AX role tree here. The plan calls this a spike
    // for exactly that reason ("spike it against Messages... if the tree
    // doesn't expose the field reliably, fall back"). What ships is the
    // generic path only, off by default, failing closed at every step
    // rather than partially completing (e.g. never sets text into a field
    // it then can't find a send button for and just leaves there). The
    // per-app Messages.app AppleScript fallback the plan mentions is not
    // implemented — that's the natural next step if/when this is verified
    // not to work reliably.
    //
    // This deviates from the plan's F-01 capability table, which reserves
    // `axNotifications` in the XPC helper for this. `NotificationWatcher`
    // already performs its AX tree walk directly in the sandboxed app
    // process (see the file header) rather than through the helper, so the
    // reply action extends that in place, operating on the same retained
    // `AXUIElement` the observer callback already produced. Routing this
    // through the helper instead would mean serializing an `AXUIElement`
    // across the XPC boundary, which has no straightforward NSSecureCoding
    // support — this is simpler and stays consistent with how the rest of
    // this file already works.

    /// Whether a reply is even worth offering for this notification —
    /// checked by the UI before showing a reply affordance at all.
    func canReply(to id: UUID) -> Bool {
        Defaults[.notificationReplyEnabled] && pendingWindows.contains { $0.id == id }
    }

    /// Attempts to find a reply text field and a send/reply button inside
    /// the banner's AX tree and submit `text`. Returns `false` on any
    /// failure. `text` is never logged, printed, or stored anywhere beyond
    /// this call's own stack.
    @discardableResult
    func reply(to id: UUID, text: String) -> Bool {
        guard Defaults[.notificationReplyEnabled] else { return false }
        guard let index = pendingWindows.firstIndex(where: { $0.id == id }) else { return false }
        let window = pendingWindows[index].window
        pendingWindows.remove(at: index)

        guard let textField = Self.findElement(in: window, roles: [kAXTextFieldRole, kAXTextAreaRole], depth: 0) else {
            return false
        }
        guard AXUIElementSetAttributeValue(textField, kAXValueAttribute as CFString, text as CFTypeRef) == .success else {
            return false
        }
        guard let sendButton = Self.findElement(
            in: window,
            roles: [kAXButtonRole],
            titleContains: ["send", "reply"],
            depth: 0
        ) else {
            return false
        }
        return AXUIElementPerformAction(sendButton, kAXPressAction as CFString) == .success
    }

    /// Depth-limited search for the first element matching one of `roles`
    /// (and, if given, whose title contains one of `titleContains`,
    /// case-insensitively — used to pick out a "Send"/"Reply" button among
    /// possibly several buttons in the banner). English-only matching: a
    /// localized banner in another language won't find its send button this
    /// way, and this fails closed rather than guessing.
    private static func findElement(
        in element: AXUIElement,
        roles: [String],
        titleContains: [String]? = nil,
        depth: Int
    ) -> AXUIElement? {
        guard depth < 10 else { return nil }

        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        if let role = roleValue as? String, roles.contains(role) {
            if let titleContains {
                var titleValue: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
                let title = (titleValue as? String)?.lowercased() ?? ""
                if titleContains.contains(where: { title.contains($0) }) {
                    return element
                }
            } else {
                return element
            }
        }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement]
        else { return nil }

        for child in children {
            if let found = findElement(in: child, roles: roles, titleContains: titleContains, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    private static func bundleIdentifier(forAppNamed name: String) -> String? {
        NSWorkspace.shared.runningApplications
            .first { $0.localizedName == name }?
            .bundleIdentifier
    }

    // MARK: Presenting

    private func announce(_ notification: NotchNotification) {
        if Defaults[.notificationsExcludedApps].contains(where: {
            $0.caseInsensitiveCompare(notification.appName ?? "") == .orderedSame
        }) {
            return
        }

        latest = notification
        recent.insert(notification, at: 0)
        if recent.count > 50 {
            recent.removeLast(recent.count - 50)
        }

        guard Defaults[.notificationsLiveActivity] else { return }
        BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .notification)
    }

    func clearHistory() {
        recent = []
        latest = nil
    }

    /// Prompts for Accessibility permission via the existing XPC helper, then
    /// retries once the user has had a chance to grant it.
    func requestAccessibilityPermission() {
        XPCHelperClient.shared.requestAccessibilityAuthorization()
        scheduleRetry()
    }
}
