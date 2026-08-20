//
//  ScreenshotEditorModel.swift
//  boringNotch
//
//  F-12: annotation state for the screenshot editor. Everything is stored in
//  the screenshot's own pixel coordinate space (top-left origin, y-down —
//  SwiftUI `Canvas`'s space) so the same points draw correctly whether the
//  canvas is shown scaled-down on screen or rendered at full size for export
//  — see `ScreenshotEditorView`'s `.scaleEffect` for how that stays true
//  without any manual coordinate math.
//

import SwiftUI

enum ScreenshotEditorTool: String, CaseIterable, Identifiable {
    case arrow
    case rectangle
    case freehand
    case text
    case blur
    case crop

    var id: String { rawValue }

    var label: String {
        switch self {
        case .arrow: return NSLocalizedString("screenshot_editor_tool_arrow", comment: "Screenshot editor tool: arrow")
        case .rectangle: return NSLocalizedString("screenshot_editor_tool_rectangle", comment: "Screenshot editor tool: rectangle")
        case .freehand: return NSLocalizedString("screenshot_editor_tool_freehand", comment: "Screenshot editor tool: freehand")
        case .text: return NSLocalizedString("screenshot_editor_tool_text", comment: "Screenshot editor tool: text")
        case .blur: return NSLocalizedString("screenshot_editor_tool_blur", comment: "Screenshot editor tool: blur")
        case .crop: return NSLocalizedString("screenshot_editor_tool_crop", comment: "Screenshot editor tool: crop")
        }
    }

    var iconName: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .freehand: return "scribble"
        case .text: return "textformat"
        case .blur: return "drop.circle"
        case .crop: return "crop"
        }
    }
}

/// One drawn element. Arrow/rectangle/blur/crop use 2 points (start, end);
/// freehand uses every point along the stroke; text uses 1, its top-left.
struct ScreenshotAnnotation: Identifiable {
    let id = UUID()
    var tool: ScreenshotEditorTool
    var points: [CGPoint]
    var text: String = ""
    var color: Color = .red

    static func rect(from points: [CGPoint]) -> CGRect {
        guard points.count >= 2 else { return .zero }
        let a = points[0], b = points[1]
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

@MainActor
final class ScreenshotEditorModel: ObservableObject {
    let baseImage: NSImage
    let imageSize: CGSize

    @Published var annotations: [ScreenshotAnnotation] = []
    @Published var tool: ScreenshotEditorTool = .arrow
    @Published var color: Color = .red
    /// Applied last, at export.
    @Published var cropRect: CGRect?

    @Published private(set) var draftAnnotation: ScreenshotAnnotation?
    @Published var textEntryOrigin: CGPoint?
    @Published var draftText: String = ""

    init(image: NSImage) {
        self.baseImage = image
        self.imageSize = image.size
    }

    var hasEdits: Bool { !annotations.isEmpty || cropRect != nil }

    func beginStroke(at point: CGPoint) {
        guard tool != .text else {
            textEntryOrigin = point
            draftText = ""
            return
        }
        draftAnnotation = ScreenshotAnnotation(tool: tool, points: [point], color: color)
    }

    func extendStroke(to point: CGPoint) {
        guard var annotation = draftAnnotation else { return }
        if annotation.tool == .freehand {
            annotation.points.append(point)
        } else if annotation.points.count > 1 {
            annotation.points[1] = point
        } else {
            annotation.points.append(point)
        }
        draftAnnotation = annotation
    }

    func endStroke() {
        guard let annotation = draftAnnotation else { return }
        draftAnnotation = nil

        guard annotation.points.count >= 2 else { return }

        if annotation.tool == .crop {
            let rect = ScreenshotAnnotation.rect(from: annotation.points)
            cropRect = rect.intersection(CGRect(origin: .zero, size: imageSize))
        } else {
            annotations.append(annotation)
        }
    }

    func commitText() {
        defer {
            textEntryOrigin = nil
            draftText = ""
        }
        guard let origin = textEntryOrigin, !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        annotations.append(ScreenshotAnnotation(tool: .text, points: [origin], text: draftText, color: color))
    }

    func cancelTextEntry() {
        textEntryOrigin = nil
        draftText = ""
    }

    func undo() {
        if !annotations.isEmpty {
            annotations.removeLast()
        } else {
            cropRect = nil
        }
    }
}
