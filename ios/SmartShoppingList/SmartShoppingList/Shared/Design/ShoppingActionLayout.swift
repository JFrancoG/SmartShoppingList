import SwiftUI

/// Uses the immediate layout proposal, including a fold-adapted group's narrower width.
struct ShoppingActionLayout: Layout {
    var widthFraction: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let label = subviews.first else { return .zero }
        let available = proposal.width ?? label.sizeThatFits(.unspecified).width
        let width = min(available, max(44, available * widthFraction))
        let size = label.sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}
