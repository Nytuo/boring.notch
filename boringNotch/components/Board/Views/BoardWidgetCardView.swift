//
//  BoardWidgetCardView.swift
//  boringNotch
//
//  F-11: one placed widget's chrome — the size class's height, a remove
//  badge and a size cycle button while editing.
//

import SwiftUI

struct BoardWidgetCardView: View {
    let widget: BoardWidgetDescriptor
    let size: BoardWidgetSize
    let isEditing: Bool
    let onRemove: () -> Void
    let onCycleSize: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            widget.content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(10)
                .frame(height: size.height)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(alignment: .bottomTrailing) {
                    if isEditing {
                        Button(action: onCycleSize) {
                            Text(size.label)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                    }
                }

            if isEditing {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, .red)
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
        }
    }
}
