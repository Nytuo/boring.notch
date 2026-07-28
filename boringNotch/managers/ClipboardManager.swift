//
//  ClipboardManager.swift
//  boringNotch
//
//  Clipboard history: polls NSPasteboard, keeps a capped ring of entries and
//  can paste them back.
//

import AppKit
import Combine
import CryptoKit
import Defaults
import Foundation
import SwiftUI

// MARK: - Model

struct ClipboardEntry: Identifiable, Codable, Equatable {
    enum Payload: Codable, Equatable {
        case text(String)
        case image(Data)
        case fileURLs([URL])
    }

    let id: UUID
    let payload: Payload
    let createdAt: Date
    /// Bundle identifier of the app that was frontmost when this was copied.
    let sourceBundleID: String?
    /// Hash of the content, used to collapse consecutive duplicates cheaply.
    let contentHash: String

    var isPinned: Bool = false

    var previewText: String {
        switch payload {
        case .text(let value):
            let collapsed = value
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return collapsed.isEmpty ? value : collapsed
        case .image:
            return NSLocalizedString("clipboard_image", comment: "Clipboard entry that is an image")
        case .fileURLs(let urls):
            if urls.count == 1 {
                return urls[0].lastPathComponent
            }
            return String(
                format: NSLocalizedString(
                    "clipboard_files_count",
                    comment: "Clipboard entry with several files"
                ),
                urls.count
            )
        }
    }

    var iconName: String {
        switch payload {
        case .text(let value):
            if value.hasPrefix("http://") || value.hasPrefix("https://") {
                return "link"
            }
            return "text.alignleft"
        case .image:
            return "photo"
        case .fileURLs:
            return "doc"
        }
    }

    var image: NSImage? {
        guard case .image(let data) = payload else { return nil }
        return ClipboardImageCache.image(for: contentHash, data: data)
    }

    /// Text with its line breaks intact, for the multi-line card preview.
    /// `previewText` collapses them, which is right for a one-line row but
    /// throws away the shape of code and addresses.
    var multilineText: String? {
        guard case .text(let value) = payload else { return nil }
        return value
    }

    var fileURLs: [URL] {
        guard case .fileURLs(let urls) = payload else { return [] }
        return urls
    }

    var isLink: Bool {
        guard case .text(let value) = payload else { return false }
        return value.hasPrefix("http://") || value.hasPrefix("https://")
    }

    /// Short right-aligned detail for the card footer: size for images, item
    /// count for files, length for text.
    var detailText: String {
        switch payload {
        case .text(let value):
            let count = value.count
            return String(
                format: NSLocalizedString(
                    "clipboard_characters_count",
                    comment: "Length of a copied text entry"
                ),
                count
            )
        case .image:
            guard let size = image?.size else { return "" }
            return "\(Int(size.width))×\(Int(size.height))"
        case .fileURLs(let urls):
            return String(
                format: NSLocalizedString(
                    "clipboard_files_count",
                    comment: "Clipboard entry with several files"
                ),
                urls.count
            )
        }
    }

    /// Kind label used as the card's caption.
    var kindLabel: String {
        switch payload {
        case .text:
            return isLink
                ? NSLocalizedString("clipboard_kind_link", comment: "Clipboard entry kind: link")
                : NSLocalizedString("clipboard_kind_text", comment: "Clipboard entry kind: text")
        case .image:
            return NSLocalizedString("clipboard_kind_image", comment: "Clipboard entry kind: image")
        case .fileURLs:
            return NSLocalizedString("clipboard_kind_files", comment: "Clipboard entry kind: files")
        }
    }
}

/// Decoding a PNG is not free, and the card grid asks for the same images on
/// every layout pass, so they are decoded once and kept until memory pressure
/// takes them back.
private enum ClipboardImageCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 120
        return cache
    }()

    static func image(for key: String, data: Data) -> NSImage? {
        if let cached = cache.object(forKey: key as NSString) { return cached }
        guard let decoded = NSImage(data: data) else { return nil }
        cache.setObject(decoded, forKey: key as NSString)
        return decoded
    }
}

// MARK: - Manager

@MainActor
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published private(set) var entries: [ClipboardEntry] = []
    @Published var searchQuery: String = ""

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var pollTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// Set while the manager itself writes to the pasteboard, so restoring an
    /// entry does not immediately re-record it as a new copy.
    private var isWritingToPasteboard = false

    private static let storageURL = documentsDirectory
        .appendingPathComponent("clipboard-history.json")

    private init() {
        lastChangeCount = pasteboard.changeCount

        Defaults.publisher(.clipboardHistoryEnabled)
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

        Defaults.publisher(.clipboardHistoryLimit)
            .sink { [weak self] _ in
                Task { @MainActor in self?.trim() }
            }
            .store(in: &cancellables)

        if Defaults[.clipboardPersistHistory] {
            load()
        }
        if Defaults[.clipboardHistoryEnabled] {
            start()
        }
    }

    // MARK: Lifecycle

    func start() {
        guard pollTask == nil else { return }
        lastChangeCount = pasteboard.changeCount
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.poll()
                // NSPasteboard has no change notification, so polling is the
                // only option. 0.5s is responsive without being costly.
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: Polling

    private func poll() {
        guard !isWritingToPasteboard else { return }
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        guard Defaults[.clipboardHistoryEnabled] else { return }
        guard !shouldIgnoreCurrentPasteboard() else { return }

        let sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let sourceBundleID, Defaults[.clipboardExcludedApps].contains(sourceBundleID) {
            return
        }

        guard let payload = readPayload() else { return }
        let hash = Self.hash(payload)

        // Collapse repeats: re-copying the same thing moves it to the top
        // rather than creating a second identical row.
        if let index = entries.firstIndex(where: { $0.contentHash == hash }) {
            let existing = entries.remove(at: index)
            entries.insert(existing, at: 0)
            persistIfNeeded()
            return
        }

        let entry = ClipboardEntry(
            id: UUID(),
            payload: payload,
            createdAt: Date(),
            sourceBundleID: sourceBundleID,
            contentHash: hash
        )
        entries.insert(entry, at: 0)
        trim()
        persistIfNeeded()
    }

    /// Honours the pasteboard's own "do not record" markers, which password
    /// managers set when they put a secret on the clipboard.
    private func shouldIgnoreCurrentPasteboard() -> Bool {
        guard Defaults[.clipboardIgnoreConfidential] else { return false }
        let types = pasteboard.types ?? []
        let confidentialMarkers: Set<String> = [
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.TransientType",
            "org.nspasteboard.AutoGeneratedType",
            "com.agilebits.onepassword"
        ]
        return types.contains { confidentialMarkers.contains($0.rawValue) }
    }

    private func readPayload() -> ClipboardEntry.Payload? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           !urls.isEmpty,
           urls.allSatisfy(\.isFileURL) {
            return .fileURLs(urls)
        }

        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(text)
        }

        if Defaults[.clipboardStoreImages],
           let data = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            // Re-encode to PNG: TIFF from the pasteboard is often many times
            // larger, which matters when we keep a hundred of them.
            if let bitmap = NSBitmapImageRep(data: data),
               let png = bitmap.representation(using: .png, properties: [:]) {
                return .image(png)
            }
            return .image(data)
        }

        return nil
    }

    private static func hash(_ payload: ClipboardEntry.Payload) -> String {
        var data = Data()
        switch payload {
        case .text(let value):
            data = Data(value.utf8)
        case .image(let imageData):
            data = imageData
        case .fileURLs(let urls):
            data = Data(urls.map(\.absoluteString).joined(separator: "\n").utf8)
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Mutations

    /// Puts an entry back on the pasteboard.
    func copyToPasteboard(_ entry: ClipboardEntry) {
        isWritingToPasteboard = true
        defer {
            // Adopt the new change count so our own write is not re-recorded.
            lastChangeCount = pasteboard.changeCount
            isWritingToPasteboard = false
        }

        pasteboard.clearContents()
        switch entry.payload {
        case .text(let value):
            pasteboard.setString(value, forType: .string)
        case .image(let data):
            pasteboard.setData(data, forType: .png)
        case .fileURLs(let urls):
            pasteboard.writeObjects(urls as [NSURL])
        }
    }

    func togglePin(_ entry: ClipboardEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isPinned.toggle()
        persistIfNeeded()
    }

    func delete(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
        persistIfNeeded()
    }

    /// Clears everything except pinned entries.
    func clearHistory() {
        entries.removeAll { !$0.isPinned }
        persistIfNeeded()
    }

    /// Entries matching the current search, pinned ones first.
    var filteredEntries: [ClipboardEntry] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matching = query.isEmpty
            ? entries
            : entries.filter { $0.previewText.lowercased().contains(query) }
        return matching.filter(\.isPinned) + matching.filter { !$0.isPinned }
    }

    private func trim() {
        let limit = max(10, Defaults[.clipboardHistoryLimit])
        guard entries.count > limit else { return }

        // Pinned entries are never evicted; the cap applies to the rest.
        var kept: [ClipboardEntry] = []
        var unpinnedCount = 0
        for entry in entries {
            if entry.isPinned {
                kept.append(entry)
            } else if unpinnedCount < limit {
                kept.append(entry)
                unpinnedCount += 1
            }
        }
        entries = kept
    }

    // MARK: Persistence

    private func persistIfNeeded() {
        guard Defaults[.clipboardPersistHistory] else { return }
        let snapshot = entries
        Task.detached(priority: .background) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: Self.storageURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storageURL),
              let decoded = try? JSONDecoder().decode([ClipboardEntry].self, from: data)
        else { return }
        entries = decoded
    }

    /// Removes the on-disk copy, for when persistence is switched off.
    func deletePersistedHistory() {
        try? FileManager.default.removeItem(at: Self.storageURL)
    }
}
