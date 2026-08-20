//
//  ScreenshotEditorPresenter.swift
//  boringNotch
//
//  F-12: owns the editor's window. A regular window rather than a sheet on
//  the notch panel — the notch panel is a borderless, deliberately small
//  overlay, not somewhere an editing surface belongs.
//

import AppKit
import SwiftUI

@MainActor
final class ScreenshotEditorPresenter: NSObject, NSWindowDelegate {
    static let shared = ScreenshotEditorPresenter()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func present(url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }

        window?.close()
        ScreenshotManager.shared.beginEditing()

        let view = ScreenshotEditorView(
            image: image,
            onSave: { [weak self] edited in
                ScreenshotManager.shared.saveEditedImage(edited, to: url)
                self?.close()
            },
            onCancel: { [weak self] in
                self?.close()
            }
        )

        let hosting = NSHostingController(rootView: view)
        let editorWindow = NSWindow(contentViewController: hosting)
        editorWindow.title = NSLocalizedString("screenshot_editor_title", comment: "Screenshot editor window title")
        editorWindow.styleMask = [.titled, .closable]
        editorWindow.isReleasedWhenClosed = false
        editorWindow.delegate = self
        editorWindow.center()
        window = editorWindow

        NSApp.activate(ignoringOtherApps: true)
        editorWindow.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        ScreenshotManager.shared.endEditing()
        window = nil
    }

    private func close() {
        window?.close()
    }
}
