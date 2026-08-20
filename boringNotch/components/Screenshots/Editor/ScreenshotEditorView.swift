//
//  ScreenshotEditorView.swift
//  boringNotch
//
//  F-12: crop, arrow, box, freehand, text and blur, then save-in-place, copy
//  or add to shelf. The canvas is laid out at the screenshot's native pixel
//  size and shown scaled down with `.scaleEffect`, which SwiftUI reports
//  gesture locations through unaffected by — so every annotation point is
//  recorded in image-space with no manual scale math, and exporting at full
//  resolution reuses the exact same draw calls as the on-screen preview.
//

import SwiftUI

struct ScreenshotEditorView: View {
    @StateObject private var model: ScreenshotEditorModel
    let onSave: (NSImage) -> Void
    let onCancel: () -> Void

    private static let maxDisplaySize = CGSize(width: 760, height: 540)

    init(image: NSImage, onSave: @escaping (NSImage) -> Void, onCancel: @escaping () -> Void) {
        _model = StateObject(wrappedValue: ScreenshotEditorModel(image: image))
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var displayScale: CGFloat {
        guard model.imageSize.width > 0, model.imageSize.height > 0 else { return 1 }
        return min(
            Self.maxDisplaySize.width / model.imageSize.width,
            Self.maxDisplaySize.height / model.imageSize.height,
            1
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            ZStack(alignment: .topLeading) {
                canvas
                    .scaleEffect(displayScale, anchor: .topLeading)
                    .frame(
                        width: model.imageSize.width * displayScale,
                        height: model.imageSize.height * displayScale
                    )
                    .clipped()

                if let origin = model.textEntryOrigin {
                    textEntryField(at: CGPoint(x: origin.x * displayScale, y: origin.y * displayScale))
                }
            }
            .background(Color.black.opacity(0.4))
            .padding(12)

            footer
        }
        .frame(width: Self.maxDisplaySize.width + 24)
    }

    private var canvas: some View {
        Canvas { context, size in
            ScreenshotEditorRenderer.render(
                image: model.baseImage,
                annotations: model.annotations,
                draft: model.draftAnnotation,
                cropRect: model.cropRect,
                showCropOverlay: true,
                in: context,
                size: size
            )
        }
        .frame(width: model.imageSize.width, height: model.imageSize.height)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if model.draftAnnotation == nil {
                        model.beginStroke(at: value.startLocation)
                    }
                    model.extendStroke(to: value.location)
                }
                .onEnded { _ in
                    model.endStroke()
                }
        )
    }

    private func textEntryField(at point: CGPoint) -> some View {
        let field = TextField("", text: $model.draftText, onCommit: { model.commitText() })
            .textFieldStyle(.plain)
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(model.color)
            .padding(4)
        let styled = field
            .background(Color.black.opacity(0.6))
            .cornerRadius(4)
            .frame(width: 160)
        return styled
            .position(x: point.x + 80, y: point.y + 14)
            .onExitCommand { model.cancelTextEntry() }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            ForEach(ScreenshotEditorTool.allCases) { tool in
                Button {
                    model.tool = tool
                } label: {
                    Image(systemName: tool.iconName)
                        .frame(width: 28, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(model.tool == tool ? Color.effectiveAccent.opacity(0.3) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(tool.label)
            }

            Divider().frame(height: 18)

            ColorPicker("", selection: $model.color, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 26)

            Spacer()

            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.plain)
            .disabled(!model.hasEdits)
            .help(NSLocalizedString("screenshot_editor_undo", comment: "Undo the last edit"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Button(NSLocalizedString("screenshot_editor_cancel", comment: "Cancel editing")) {
                onCancel()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(NSLocalizedString("screenshot_editor_save", comment: "Save the edited screenshot")) {
                onSave(exportImage())
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    /// Renders at the screenshot's native resolution — the same draw calls as
    /// the on-screen canvas, without the crop-guide overlay. The crop is
    /// applied by translating the drawing and letting a canvas frame sized to
    /// just the crop region clip everything else, rather than cropping the
    /// rendered `CGImage` after the fact — `CGImage.cropping(to:)` uses a
    /// bottom-left-origin rect, which would need flipping against the
    /// top-left-origin space every point in this editor is otherwise stored
    /// and drawn in, and getting that flip wrong is exactly the kind of bug
    /// there's no way to visually catch here. Staying inside SwiftUI's one
    /// coordinate convention end to end avoids the question entirely.
    private func exportImage() -> NSImage {
        let crop = model.cropRect
        let outputSize = crop?.size ?? model.imageSize
        let offset = crop?.origin ?? .zero

        guard outputSize.width > 1, outputSize.height > 1 else { return model.baseImage }

        let baseImage = model.baseImage
        let annotations = model.annotations
        let fullSize = model.imageSize

        let renderer = ImageRenderer(content:
            Canvas { context, _ in
                context.translateBy(x: -offset.x, y: -offset.y)
                ScreenshotEditorRenderer.render(
                    image: baseImage,
                    annotations: annotations,
                    draft: nil,
                    cropRect: nil,
                    showCropOverlay: false,
                    in: context,
                    size: fullSize
                )
            }
            .frame(width: outputSize.width, height: outputSize.height)
        )
        renderer.scale = 1

        return renderer.nsImage ?? model.baseImage
    }
}
