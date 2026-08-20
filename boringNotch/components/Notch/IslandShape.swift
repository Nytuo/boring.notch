//
//  IslandShape.swift
//  boringNotch
//
//  F-04: `NotchShape` assumes a cutout flush with a physical bezel — its top
//  corners are square so the shape reads as continuous with the screen edge.
//  A notchless display has no bezel to blend into, so the panel needs to read
//  as a freestanding pill instead: every corner rounded, not just the bottom
//  two. Mirrors `NotchShape`'s animatable-corner-radius pattern so the two
//  drop into the same call sites interchangeably.
//

import SwiftUI

struct IslandShape: Shape {
    private var cornerRadius: CGFloat

    init(cornerRadius: CGFloat? = nil) {
        self.cornerRadius = cornerRadius ?? 14
    }

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        return Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
    }
}

#Preview {
    IslandShape(cornerRadius: 14)
        .frame(width: 200, height: 32)
        .padding(10)
}
