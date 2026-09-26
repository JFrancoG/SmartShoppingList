import SwiftUI

/// Sizes a single control group inside local division regions; list rows keep their full width.
struct ShoppingControlLayout: Layout {
    var divisions: [CGRect]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let width = proposal.width ?? content.sizeThatFits(.unspecified).width
        let placement = placement(width: width, content: content)
        return CGSize(width: width, height: placement.maxY)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let frame = placement(width: bounds.width, content: content)
        content.place(
            at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: frame.width, height: frame.height)
        )
    }

    private func placement(width: CGFloat, content: LayoutSubview) -> CGRect {
        let horizontal = ShoppingControlPlacement.horizontalRange(width: width, divisions: divisions)
        let size = content.sizeThatFits(ProposedViewSize(width: horizontal.width, height: nil))
        return ShoppingControlPlacement.frame(size: size, horizontal: horizontal, divisions: divisions)
    }
}

/// Pure geometry policy, independent of device models and observable application state.
enum ShoppingControlPlacement {
    static func horizontalRange(width: CGFloat, divisions: [CGRect]) -> CGRect {
        var range = CGRect(x: 0, y: 0, width: max(0, width), height: 0)
        for division in divisions where division.height > division.width {
            guard division.minX < range.maxX, division.maxX > range.minX else { continue }
            let trailingWidth = max(0, range.maxX - division.maxX)
            let leadingWidth = max(0, division.minX - range.minX)
            if trailingWidth >= 44 || trailingWidth >= leadingWidth {
                range = CGRect(x: max(range.minX, division.maxX), y: 0, width: trailingWidth, height: 0)
            } else {
                range.size.width = leadingWidth
            }
        }
        return range
    }

    static func frame(size: CGSize, horizontal: CGRect, divisions: [CGRect]) -> CGRect {
        var frame = CGRect(x: horizontal.minX, y: 0, width: horizontal.width, height: size.height)
        for division in divisions where division.width >= division.height {
            if frame.intersects(division) {
                frame.origin.y = max(0, division.maxY)
            }
        }
        return frame
    }
}
