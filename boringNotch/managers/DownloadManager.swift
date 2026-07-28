//
//  DownloadManager.swift
//  boringNotch
//
//  Watches the Downloads folder for in-progress browser downloads and reports
//  them as notch live activities.
//
//  Browsers write a partial file while downloading and rename it on completion,
//  so watching for those temporary files works across every browser without
//  needing to talk to the browser itself:
//
//    Safari    Foo.zip.download   (a bundle directory)
//    Chromium  Foo.zip.crdownload
//    Firefox   Foo.zip.part
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

// MARK: - Model

enum DownloadBrowser: String, Codable, CaseIterable {
    case safari
    case chromium
    case firefox

    /// Partial-file suffix this browser uses.
    var partialExtension: String {
        switch self {
        case .safari: return "download"
        case .chromium: return "crdownload"
        case .firefox: return "part"
        }
    }

    var displayName: String {
        switch self {
        case .safari: return "Safari"
        case .chromium: return "Chromium"
        case .firefox: return "Firefox"
        }
    }

    /// Bundle identifier used to draw the app icon. Picks whichever
    /// Chromium-family browser is actually installed.
    @MainActor
    var iconBundleID: String {
        switch self {
        case .safari:
            return "com.apple.Safari"
        case .firefox:
            return "org.mozilla.firefox"
        case .chromium:
            let candidates = [
                "com.google.Chrome",
                "com.brave.Browser",
                "com.microsoft.edgemac",
                "com.vivaldi.Vivaldi",
                "com.operasoftware.Opera",
                "company.thebrowser.Browser"
            ]
            let workspace = NSWorkspace.shared
            return candidates.first { workspace.urlForApplication(withBundleIdentifier: $0) != nil }
                ?? "com.google.Chrome"
        }
    }

    static func forPartialFile(at url: URL) -> DownloadBrowser? {
        allCases.first { $0.partialExtension == url.pathExtension }
    }
}

struct ActiveDownload: Identifiable, Equatable {
    /// Path of the partial file, which is stable for the download's lifetime.
    var id: String { partialURL.path }

    let partialURL: URL
    let browser: DownloadBrowser
    /// Name the file will have once complete (the partial suffix removed).
    let fileName: String
    var bytesDownloaded: Int64
    /// Total size when the browser records it; `nil` when unknown.
    var totalBytes: Int64?
    let startedAt: Date
    /// Smoothed transfer rate, `nil` until two samples exist.
    var bytesPerSecond: Double?

    /// 0...1, or `nil` when the total size is unknown.
    var progress: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1.0, Double(bytesDownloaded) / Double(totalBytes))
    }

    var formattedProgress: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let downloaded = formatter.string(fromByteCount: bytesDownloaded)
        if let totalBytes, totalBytes > 0 {
            return "\(downloaded) / \(formatter.string(fromByteCount: totalBytes))"
        }
        return downloaded
    }

    var percentText: String? {
        guard let progress else { return nil }
        return "\(Int((progress * 100).rounded()))%"
    }

    /// Rate as "1.2 MB/s", or `nil` while it is still being measured.
    var formattedSpeed: String? {
        guard let bytesPerSecond, bytesPerSecond > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.allowsNonnumericFormatting = false
        return "\(formatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }
}

// MARK: - Manager

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var activeDownloads: [ActiveDownload] = []
    /// `true` when watching is on but the Downloads folder has not been granted.
    @Published private(set) var needsFolderAccess = false
    /// Name of the last file that landed, for the completion banner.
    @Published private(set) var lastCompletedFileName: String?

    private var folderSource: DispatchSourceFileSystemObject?
    private var pollTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    /// The folder currently being watched.
    private var watchedURL: URL?
    /// Last size sample per download, for working out the transfer rate.
    private var rateSamples: [String: (bytes: Int64, date: Date)] = [:]
    /// Finished files seen on the previous scan, so an arrival can be spotted.
    private var knownFiles: Set<String> = []
    private var hasSeededKnownFiles = false
    /// Set only when that folder came from a bookmark, so the security scope is
    /// closed again on stop.
    private var accessedURL: URL?

    private init() {
        Defaults.publisher(.enableDownloadListener)
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

        if Defaults[.enableDownloadListener] {
            start()
        }
    }

    // MARK: Folder access

    /// Where to watch, and whether that location needs a security scope opened
    /// around it.
    private struct DownloadsFolder {
        let url: URL
        /// Bookmarked folders are security-scoped; the entitled Downloads
        /// folder is readable directly and must not be scope-wrapped.
        let isSecurityScoped: Bool
    }

    /// The folder to watch.
    ///
    /// The app is sandboxed, but `com.apple.security.files.downloads.read-only`
    /// grants the user's Downloads folder with no prompt, so the common case
    /// needs no setup at all. A bookmark is only used when the user has pointed
    /// the watcher somewhere else.
    private func resolveDownloadsFolder() -> DownloadsFolder? {
        if let data = Defaults[.downloadsFolderBookmark] {
            let bookmark = Bookmark(data: data)
            let (url, refreshed) = bookmark.resolve()
            if let refreshed {
                Defaults[.downloadsFolderBookmark] = refreshed
            }
            if let url {
                return DownloadsFolder(url: url, isSecurityScoped: true)
            }
        }

        guard let url = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first
        else { return nil }
        return DownloadsFolder(url: url, isSecurityScoped: false)
    }

    /// Prompts for a folder to watch.
    ///
    /// Only needed when the entitled Downloads folder is unavailable or the
    /// user keeps downloads somewhere else; a user-selected grant is the only
    /// route to anywhere outside it.
    func requestDownloadsFolderAccess() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.prompt = NSLocalizedString("downloads_grant_prompt", comment: "Open panel button to grant Downloads access")
        panel.message = NSLocalizedString("downloads_grant_message", comment: "Open panel message explaining why access is needed")

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let bookmark = try Bookmark(url: url)
            Defaults[.downloadsFolderBookmark] = bookmark.data
            needsFolderAccess = false
            stop()
            start()
        } catch {
            NSLog("❌ Downloads: could not bookmark \(url.path): \(error.localizedDescription)")
        }
    }

    // MARK: Lifecycle

    func start() {
        stop()

        guard Defaults[.enableDownloadListener] else { return }

        guard let folder = resolveDownloadsFolder() else {
            needsFolderAccess = true
            return
        }

        if folder.isSecurityScoped {
            guard folder.url.startAccessingSecurityScopedResource() else {
                needsFolderAccess = true
                return
            }
            accessedURL = folder.url
        }

        // Readable is not the same as granted: the entitled folder still fails
        // to open if the user has denied it at the system level.
        guard FileManager.default.isReadableFile(atPath: folder.url.path) else {
            needsFolderAccess = true
            return
        }

        watchedURL = folder.url
        needsFolderAccess = false

        // A directory watch fires when files appear or disappear, which covers
        // downloads starting and finishing.
        let descriptor = open(folder.url.path, O_EVTONLY)
        if descriptor >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.scan() }
            }
            // Closes *this* descriptor, captured by value. Reading it back off
            // the manager would be a bug: cancellation is asynchronous, so by
            // the time an old source tears down, a restart has already opened a
            // new descriptor — and descriptor numbers get reused, so the old
            // handler would close the live watch and silently stop events.
            source.setCancelHandler {
                close(descriptor)
            }
            source.resume()
            folderSource = source
        }

        // The directory watch does not fire as a partial file *grows*, so poll
        // while something is in flight to keep the progress bar moving. Idle,
        // it ticks over slowly as a safety net in case an event is missed.
        pollTask = Task { @MainActor [weak self] in
            var idleTicks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                guard let self else { continue }
                if self.activeDownloads.isEmpty {
                    idleTicks += 1
                    guard idleTicks >= 7 else { continue }
                }
                idleTicks = 0
                self.scan()
            }
        }

        scan()
    }

    func stop() {
        folderSource?.cancel()
        folderSource = nil
        pollTask?.cancel()
        pollTask = nil
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
        watchedURL = nil
        activeDownloads = []
        // Re-seed on the next start, so restarting does not announce every file
        // already sitting in the folder.
        knownFiles = []
        hasSeededKnownFiles = false
    }

    // MARK: Scanning

    private func scan() {
        guard let folder = watchedURL else { return }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var found: [ActiveDownload] = []

        for url in contents {
            guard let browser = DownloadBrowser.forPartialFile(at: url) else { continue }
            guard isBrowserEnabled(browser) else { continue }

            let bytes = sizeOfPartial(at: url)
            let fileName = url.deletingPathExtension().lastPathComponent

            // Preserve the original start time across rescans so the entry does
            // not look like it restarts every poll.
            let existing = activeDownloads.first { $0.id == url.path }

            found.append(
                ActiveDownload(
                    partialURL: url,
                    browser: browser,
                    fileName: fileName,
                    bytesDownloaded: bytes,
                    totalBytes: expectedSize(for: url, browser: browser, current: bytes, existing: existing),
                    startedAt: existing?.startedAt ?? Date(),
                    bytesPerSecond: rate(for: url.path, bytes: bytes, previous: existing)
                )
            )
        }

        // Forget the rate history of anything that is no longer in flight.
        let live = Set(found.map(\.id))
        rateSamples = rateSamples.filter { live.contains($0.key) }

        let previous = Set(activeDownloads.map(\.id))
        let current = Set(found.map(\.id))

        activeDownloads = found.sorted { $0.startedAt < $1.startedAt }

        let arrived = newlyArrivedFile(in: contents)

        if !current.isEmpty && current != previous {
            // Something started: surface it.
            BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .download)
        } else if arrived != nil || (current.isEmpty && !previous.isEmpty) {
            // Something landed: show a completion flash.
            BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .download)
        }
    }

    /// Name of a file that has just appeared in the folder, if any.
    ///
    /// Watching partial files alone misses downloads that never have one: a
    /// small or cached file can land complete, and Safari in particular skips
    /// the `.download` bundle for those. Noticing the finished file means the
    /// notch still says something when a download is made.
    private func newlyArrivedFile(in contents: [URL]) -> String? {
        let files = contents.filter { url in
            // Partials are already tracked; their eventual rename shows up here
            // as the finished file.
            guard DownloadBrowser.forPartialFile(at: url) == nil else { return false }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory != true
        }
        let paths = Set(files.map(\.path))
        defer { knownFiles = paths }

        // The first scan is the baseline: everything already in the folder is
        // not news.
        guard hasSeededKnownFiles else {
            hasSeededKnownFiles = true
            return nil
        }

        let appeared = paths.subtracting(knownFiles)
            .filter { !ScreenshotManager.shared.claims(URL(fileURLWithPath: $0)) }
        guard let path = appeared.sorted().first else { return nil }

        let name = URL(fileURLWithPath: path).lastPathComponent
        lastCompletedFileName = name
        return name
    }

    /// Transfer rate for one download.
    ///
    /// Measured between scans and smoothed, because raw samples jump around:
    /// the poll interval is not exact and browsers flush to disk in bursts, so
    /// an unsmoothed number is unreadable.
    private func rate(for id: String, bytes: Int64, previous: ActiveDownload?) -> Double? {
        let now = Date()
        defer { rateSamples[id] = (bytes, now) }

        guard let sample = rateSamples[id] else { return previous?.bytesPerSecond }

        let elapsed = now.timeIntervalSince(sample.date)
        // Too small an interval turns rounding noise into a huge rate.
        guard elapsed >= 0.25 else { return previous?.bytesPerSecond }

        let delta = Double(bytes - sample.bytes)
        guard delta >= 0 else { return previous?.bytesPerSecond }

        let instant = delta / elapsed
        guard let smoothed = previous?.bytesPerSecond else { return instant }
        return smoothed * 0.7 + instant * 0.3
    }

    private func isBrowserEnabled(_ browser: DownloadBrowser) -> Bool {
        switch browser {
        case .safari: return Defaults[.enableSafariDownloads]
        case .chromium: return Defaults[.enableChromiumDownloads]
        case .firefox: return Defaults[.enableFirefoxDownloads]
        }
    }

    /// Bytes on disk so far.
    ///
    /// Safari's `.download` is a *directory* holding the partial data, so its
    /// size has to be summed rather than read from the entry itself.
    private func sizeOfPartial(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        if values?.isDirectory == true {
            var total: Int64 = 0
            if let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let child as URL in enumerator {
                    let size = (try? child.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    total += Int64(size)
                }
            }
            return total
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return Int64(size)
    }

    /// Best-effort total size.
    ///
    /// Chromium and Firefox pre-allocate the destination file, so the allocated
    /// size is a good estimate of the total. Safari gives nothing usable, so
    /// those downloads show an indeterminate indicator. Once a total is known it
    /// is kept, since a later reading can dip below the true value.
    private func expectedSize(
        for url: URL,
        browser: DownloadBrowser,
        current: Int64,
        existing: ActiveDownload?
    ) -> Int64? {
        if let known = existing?.totalBytes, known >= current {
            return known
        }
        guard browser != .safari else { return nil }
        let allocated = (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?
            .totalFileAllocatedSize ?? 0
        let value = Int64(allocated)
        return value > current ? value : nil
    }
}
