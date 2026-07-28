//
//  ScreenshotManager.swift
//  boringNotch
//
//  Catches screenshots as they are written and offers them up in the notch.
//

import AppKit
import Combine
import Defaults
import Foundation
import UniformTypeIdentifiers

// MARK: - Model

struct CapturedScreenshot: Identifiable, Equatable {
    var id: String { url.path }

    let url: URL
    let capturedAt: Date
    /// Small preview, decoded once when the file is picked up.
    let thumbnail: NSImage?

    var fileName: String { url.lastPathComponent }

    static func == (lhs: CapturedScreenshot, rhs: CapturedScreenshot) -> Bool {
        lhs.url == rhs.url && lhs.capturedAt == rhs.capturedAt
    }
}

// MARK: - Manager

/// Watches wherever macOS saves screenshots and surfaces the newest one.
///
/// Screenshots are caught by watching the folder rather than by asking the
/// system, because there is no notification for "a screenshot was taken" — the
/// same approach the download watcher uses.
@MainActor
final class ScreenshotManager: ObservableObject {
    static let shared = ScreenshotManager()

    /// The screenshot to offer actions for, cleared when it is dealt with or
    /// when it gets stale.
    @Published private(set) var latest: CapturedScreenshot?
    /// `true` when watching is on but the folder has not been granted.
    @Published private(set) var needsFolderAccess = false

    private var folderSource: DispatchSourceFileSystemObject?
    private var cancellables = Set<AnyCancellable>()
    private var watchedURL: URL?
    private var accessedURL: URL?
    private var knownFiles: Set<String> = []
    private var hasSeededKnownFiles = false
    private var expiryTask: Task<Void, Never>?

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "pdf"]

    private init() {
        Defaults.publisher(.screenshotCatcherEnabled)
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

        if Defaults[.screenshotCatcherEnabled] {
            start()
        }
    }

    // MARK: Folder access

    /// The folder to watch.
    ///
    /// macOS saves screenshots to the Desktop unless told otherwise, and the
    /// sandbox has no entitlement covering the Desktop — so a folder the user
    /// picked once is the only way in. Pictures and Downloads are readable
    /// through entitlements, so those work with no setup if that is where the
    /// user sends screenshots.
    private func resolveFolder() -> (url: URL, isSecurityScoped: Bool)? {
        if let data = Defaults[.screenshotFolderBookmark] {
            let bookmark = Bookmark(data: data)
            let (url, refreshed) = bookmark.resolve()
            if let refreshed {
                Defaults[.screenshotFolderBookmark] = refreshed
            }
            if let url {
                return (url, true)
            }
        }

        // No grant yet: fall back to somewhere an entitlement already covers,
        // so the feature does something out of the box for people who point
        // screencapture at Pictures or Downloads.
        for name in ["Pictures", "Downloads"] {
            let url = Self.realHome.appendingPathComponent(name)
            if FileManager.default.isReadableFile(atPath: url.path) {
                return (url, false)
            }
        }
        return nil
    }

    /// The user's actual home directory.
    ///
    /// `NSHomeDirectory()` and most of `FileManager.urls(for:)` point inside the
    /// sandbox container. Only the folders whose entitlement remaps them —
    /// Downloads, notably — come back as real paths, so anything else has to be
    /// built from the password database entry.
    private static var realHome: URL {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Prompts for the folder screenshots are saved to.
    func requestFolderAccess() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = Self.realHome.appendingPathComponent("Desktop")
        panel.prompt = NSLocalizedString("screenshot_grant_prompt", comment: "Open panel button to grant screenshot folder access")
        panel.message = NSLocalizedString("screenshot_grant_message", comment: "Open panel message explaining why access is needed")

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let bookmark = try Bookmark(url: url)
            Defaults[.screenshotFolderBookmark] = bookmark.data
            needsFolderAccess = false
            stop()
            start()
        } catch {
            NSLog("❌ Screenshots: could not bookmark \(url.path): \(error.localizedDescription)")
        }
    }

    // MARK: Lifecycle

    func start() {
        stop()

        guard Defaults[.screenshotCatcherEnabled] else { return }

        guard let folder = resolveFolder() else {
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

        guard FileManager.default.isReadableFile(atPath: folder.url.path) else {
            needsFolderAccess = true
            return
        }

        watchedURL = folder.url
        needsFolderAccess = false

        let descriptor = Darwin.open(folder.url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        // Closes the descriptor captured here, never one read back off the
        // manager: cancellation is async, and descriptor numbers get reused.
        source.setCancelHandler { close(descriptor) }
        source.resume()
        folderSource = source

        scan()
    }

    func stop() {
        folderSource?.cancel()
        folderSource = nil
        expiryTask?.cancel()
        expiryTask = nil
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
        watchedURL = nil
        knownFiles = []
        hasSeededKnownFiles = false
        latest = nil
    }

    // MARK: Scanning

    private func scan() {
        guard let folder = watchedURL else { return }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let images = contents.filter { Self.imageExtensions.contains($0.pathExtension.lowercased()) }
        let paths = Set(images.map(\.path))
        defer { knownFiles = paths }

        // Everything already there when watching starts is old news.
        guard hasSeededKnownFiles else {
            hasSeededKnownFiles = true
            return
        }

        let appeared = paths.subtracting(knownFiles)
        guard !appeared.isEmpty else { return }

        // Newest wins when a burst lands at once.
        let newest = appeared
            .map { URL(fileURLWithPath: $0) }
            .max { modificationDate(of: $0) < modificationDate(of: $1) }

        guard let url = newest, looksLikeScreenshot(url) else { return }

        present(url)
    }

    /// Filters out files that merely landed in the folder — an image saved from
    /// a browser is not a screenshot.
    ///
    /// macOS names captures with a localized prefix ("Screenshot", "Capture
    /// d’écran", …), which is not something to hard-code, so recency is the
    /// test: `screencapture` writes the file the moment it is taken.
    private func looksLikeScreenshot(_ url: URL) -> Bool {
        Date().timeIntervalSince(modificationDate(of: url)) < 10
    }

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    private func present(_ url: URL) {
        let thumbnail = NSImage(contentsOf: url)
        thumbnail?.size = Self.thumbnailSize(for: thumbnail?.size ?? .zero)

        latest = CapturedScreenshot(url: url, capturedAt: Date(), thumbnail: thumbnail)

        if Defaults[.screenshotAddToShelf], Defaults[.boringShelf] {
            ShelfStateViewModel.shared.load([NSItemProvider(contentsOf: url)].compactMap { $0 })
        }

        BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .screenshot)
        scheduleExpiry()
    }

    /// Keeps the preview around for a while so the actions are reachable after
    /// the banner has gone, then lets it go.
    private func scheduleExpiry() {
        expiryTask?.cancel()
        let captured = latest
        expiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Double(Defaults[.screenshotPreviewSeconds])))
            guard !Task.isCancelled, let self, self.latest == captured else { return }
            self.latest = nil
        }
    }

    private static func thumbnailSize(for size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: 60, height: 40) }
        let scale = min(120 / size.width, 80 / size.height, 1)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// Whether a file that has just appeared belongs to this watcher.
    ///
    /// The screenshot folder can be the Downloads folder, in which case the
    /// download watcher sees the same arrival — this lets it stand aside, since
    /// a screenshot preview says more than "download complete".
    func claims(_ url: URL) -> Bool {
        guard Defaults[.screenshotCatcherEnabled], let watched = watchedURL else { return false }
        guard url.deletingLastPathComponent().standardizedFileURL == watched.standardizedFileURL else { return false }
        guard Self.imageExtensions.contains(url.pathExtension.lowercased()) else { return false }
        return looksLikeScreenshot(url)
    }

    // MARK: Actions

    func dismiss() {
        expiryTask?.cancel()
        expiryTask = nil
        latest = nil
    }

    func copyToPasteboard() {
        guard let url = latest?.url, let image = NSImage(contentsOf: url) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        dismiss()
    }

    func addToShelf() {
        guard let url = latest?.url, let provider = NSItemProvider(contentsOf: url) else { return }
        ShelfStateViewModel.shared.load([provider])
        dismiss()
    }

    func revealInFinder() {
        guard let url = latest?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        dismiss()
    }

    /// Moves the file to the bin — the point of catching a screenshot is often
    /// realising you did not want it.
    func deleteFile() {
        guard let url = latest?.url else { return }
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        dismiss()
    }
}
