//
//  UniversalLauncherManager.swift
//  boringNotch
//
//  F-14: apps + in-app actions, deliberately not files — the plan's own
//  scope guard ("this is not Raycast"). File search needs either
//  `NSMetadataQuery` (untested under this app's sandbox — no prior art in
//  this codebase to confirm it behaves as expected, and the failure mode of
//  a silently-empty result set is hard to distinguish from "no matches")
//  or broad filesystem access this app isn't entitled to. Scanning the
//  standard application directories directly, instead of via Spotlight,
//  sidesteps that uncertainty entirely — it's slower to pick up a
//  freshly-installed app until the next scan, but it's mechanically
//  predictable: either the `.app` bundle is in one of these directories or
//  it isn't.
//

import AppKit
import Defaults
import Foundation

struct LauncherAppEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleURL: URL

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: LauncherAppEntry, rhs: LauncherAppEntry) -> Bool { lhs.id == rhs.id }
}

@MainActor
final class UniversalLauncherManager: ObservableObject {
    static let shared = UniversalLauncherManager()

    @Published private(set) var installedApps: [LauncherAppEntry] = []
    @Published private(set) var recentBundleIDs: [String] = Defaults[.launcherRecentApps]

    private var hasScanned = false

    private static let searchDirectories: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/System/Applications/Utilities"),
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")
    ]

    private init() {}

    /// Scans once, lazily — called when the launcher tab first appears
    /// rather than at app launch, since nothing else needs this list.
    func ensureScanned() {
        guard !hasScanned else { return }
        hasScanned = true
        rescan()
    }

    func rescan() {
        var seenBundleIDs = Set<String>()
        var results: [LauncherAppEntry] = []

        for directory in Self.searchDirectories {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in entries where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { continue }
                guard seenBundleIDs.insert(bundleID).inserted else { continue }

                let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                results.append(LauncherAppEntry(id: bundleID, name: name, bundleURL: url))
            }
        }

        installedApps = results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func icon(for entry: LauncherAppEntry) -> NSImage {
        NSWorkspace.shared.icon(forFile: entry.bundleURL.path)
    }

    func launch(_ entry: LauncherAppEntry) {
        NSWorkspace.shared.openApplication(at: entry.bundleURL, configuration: NSWorkspace.OpenConfiguration())
        recordUsage(entry.id)
    }

    private func recordUsage(_ bundleID: String) {
        var recents = Defaults[.launcherRecentApps]
        recents.removeAll { $0 == bundleID }
        recents.insert(bundleID, at: 0)
        recents = Array(recents.prefix(20))
        Defaults[.launcherRecentApps] = recents
        recentBundleIDs = recents
    }
}
