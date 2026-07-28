//
//  NotchBannerLayout.swift
//  boringNotch
//

import SwiftUI

/// Lays out a closed-notch banner as `leading | notch | trailing`.
///
/// The notch is an opaque cutout, so the spacer standing in for it only lines
/// up with the hardware when the content either side of it is balanced. Banners
/// used to buy that with a fixed 640pt width, which left most of the bar empty
/// for short content. This gives both sides the same width — the wider of the
/// two — so the banner stays centred on the notch while only being as wide as
/// it needs to be.
///
/// Expects exactly three subviews, in order: leading content, the notch spacer,
/// trailing content.
struct NotchBannerLayout: Layout {
    /// Smallest width each side may take, so a banner with almost nothing on
    /// one side still reads as a bar rather than a sliver.
    var minimumSideWidth: CGFloat = 60

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        guard subviews.count == 3 else { return .zero }

        let leading = subviews[0].sizeThatFits(.unspecified)
        let notch = subviews[1].sizeThatFits(.unspecified)
        let trailing = subviews[2].sizeThatFits(.unspecified)

        let side = max(minimumSideWidth, leading.width, trailing.width)
        let height = proposal.height ?? max(leading.height, notch.height, trailing.height)

        return CGSize(width: 2 * side + notch.width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        guard subviews.count == 3 else { return }

        let notchWidth = subviews[1].sizeThatFits(.unspecified).width
        let side = max(0, (bounds.width - notchWidth) / 2)
        let sideProposal = ProposedViewSize(width: side, height: bounds.height)

        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: sideProposal
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + side, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: notchWidth, height: bounds.height)
        )
        subviews[2].place(
            at: CGPoint(x: bounds.minX + side + notchWidth, y: bounds.midY),
            anchor: .leading,
            proposal: sideProposal
        )
    }
}
