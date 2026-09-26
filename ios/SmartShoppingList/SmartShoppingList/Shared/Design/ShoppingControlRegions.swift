import SwiftUI

/// Viewport changes trigger displacement; ordinary scrolling must not pin a row to the fold.
struct ShoppingControlRegions: Equatable, Sendable {
    var frame = CGRect.zero
    var divisions: [CGRect] = []

    static func read(from geometry: GeometryProxy) -> Self {
        guard #available(iOS 27.1, *) else { return Self(frame: geometry.frame(in: .global)) }
        return Self(
            frame: geometry.frame(in: .global),
            divisions: geometry.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)
                .filter(\.isActive).map(\.frame)
        )
    }
}

struct ShoppingControlMeasurement: Equatable, Sendable {
    let viewport: ShoppingControlRegions
    let frame: CGRect
    let scrollOffset: CGFloat
    let mirrors: Bool
}

extension EnvironmentValues {
    @Entry var shoppingControlRegions = ShoppingControlRegions()
    @Entry var shoppingControlScrollOffset: CGFloat = 0
}
