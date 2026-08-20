//
//  ScreenshotEditorRenderer.swift
//  boringNotch
//
//  F-12: the one drawing function both the live editor canvas and the export
//  renderer call, so what's on screen while editing is exactly what gets
//  saved — no separate export code path to drift out of sync.
//

import SwiftUI

enum ScreenshotEditorRenderer {
    static func render(
        image: NSImage,
        annotations: [ScreenshotAnnotation],
        draft: ScreenshotAnnotation?,
        cropRect: CGRect?,
        showCropOverlay: Bool,
        in context: GraphicsContext,
        size: CGSize
    ) {
        let swiftUIImage = Image(nsImage: image)
        context.draw(swiftUIImage, in: CGRect(origin: .zero, size: size))

        var all = annotations
        if let draft {
            all.append(draft)
        }

        for annotation in all {
            draw(annotation, sourceImage: swiftUIImage, in: context, size: size)
        }

        if showCropOverlay, let cropRect {
            context.stroke(
                Path(cropRect),
                with: .color(.white),
                style: StrokeStyle(lineWidth: 2, dash: [6, 4])
            )
        }
    }

    private static func draw(_ annotation: ScreenshotAnnotation, sourceImage: Image, in context: GraphicsContext, size: CGSize) {
        switch annotation.tool {
        case .freehand:
            guard let first = annotation.points.first else { return }
            var path = Path()
            path.move(to: first)
            for point in annotation.points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(annotation.color), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

        case .rectangle:
            guard annotation.points.count >= 2 else { return }
            let rect = ScreenshotAnnotation.rect(from: annotation.points)
            context.stroke(Path(rect), with: .color(annotation.color), lineWidth: 4)

        case .arrow:
            guard annotation.points.count >= 2 else { return }
            context.fill(arrowPath(from: annotation.points[0], to: annotation.points[1]), with: .color(annotation.color))

        case .text:
            guard let origin = annotation.points.first else { return }
            let text = Text(annotation.text)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(annotation.color)
            context.draw(text, at: origin, anchor: .topLeading)

        case .blur:
            guard annotation.points.count >= 2 else { return }
            let rect = ScreenshotAnnotation.rect(from: annotation.points)
            context.drawLayer { layer in
                layer.clip(to: Path(rect))
                layer.addFilter(.blur(radius: 12))
                layer.draw(sourceImage, in: CGRect(origin: .zero, size: size))
            }

        case .crop:
            break
        }
    }

    /// A filled arrowhead-and-shaft shape, not a stroked line — reads better
    /// at the sizes a screenshot annotation actually gets drawn at.
    private static func arrowPath(from start: CGPoint, to end: CGPoint) -> Path {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = 18
        let headAngle: CGFloat = .pi / 7
        let shaftHalfWidth: CGFloat = 2.5

        let perpendicular = angle + .pi / 2
        let dx = shaftHalfWidth * cos(perpendicular)
        let dy = shaftHalfWidth * sin(perpendicular)

        let shaftEnd = CGPoint(
            x: end.x - headLength * 0.6 * cos(angle),
            y: end.y - headLength * 0.6 * sin(angle)
        )

        var path = Path()
        path.move(to: CGPoint(x: start.x + dx, y: start.y + dy))
        path.addLine(to: CGPoint(x: shaftEnd.x + dx, y: shaftEnd.y + dy))
        path.addLine(to: CGPoint(
            x: end.x + headLength * cos(angle - .pi + headAngle),
            y: end.y + headLength * sin(angle - .pi + headAngle)
        ))
        path.addLine(to: end)
        path.addLine(to: CGPoint(
            x: end.x + headLength * cos(angle - .pi - headAngle),
            y: end.y + headLength * sin(angle - .pi - headAngle)
        ))
        path.addLine(to: CGPoint(x: shaftEnd.x - dx, y: shaftEnd.y - dy))
        path.addLine(to: CGPoint(x: start.x - dx, y: start.y - dy))
        path.closeSubpath()
        return path
    }
}
