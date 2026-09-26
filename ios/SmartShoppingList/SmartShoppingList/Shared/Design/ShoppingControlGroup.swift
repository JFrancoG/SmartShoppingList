import SwiftUI

/// Moves related controls together without replacing their identity when the device folds.
struct ShoppingControlGroup<Content: View>: View {
    @Environment(\.shoppingControlRegions) private var viewport
    @Environment(\.shoppingControlScrollOffset) private var scrollOffset
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var observedViewport: ShoppingControlRegions?
    @State private var anchoredScrollOffset: CGFloat = 0
    @State private var divisions: [CGRect] = []
    @ViewBuilder var content: Content

    var body: some View {
        let currentViewport = viewport
        let currentScrollOffset = scrollOffset
        let mirrors = layoutDirection == .rightToLeft
        ShoppingControlLayout(divisions: divisions) {
            VStack(spacing: 16) {
                content
            }
        }
        .onGeometryChange(for: ShoppingControlMeasurement.self) { geometry in
            ShoppingControlMeasurement(
                viewport: currentViewport,
                frame: geometry.frame(in: .global),
                scrollOffset: currentScrollOffset,
                mirrors: mirrors
            )
        } action: { measurement in
            if observedViewport != measurement.viewport {
                observedViewport = measurement.viewport
                anchoredScrollOffset = measurement.scrollOffset
            }
            divisions = measurement.viewport.divisions.map { division in
                var local = division.offsetBy(
                    dx: measurement.viewport.frame.minX - measurement.frame.minX,
                    dy: measurement.viewport.frame.minY - measurement.frame.minY
                )
                if division.width >= division.height {
                    // Cancel only scrolling; content growth and natural row movement still update the gap.
                    local.origin.y -= measurement.scrollOffset - anchoredScrollOffset
                }
                if measurement.mirrors {
                    local.origin.x = measurement.frame.width - local.maxX
                }
                return local
            }
        }
    }
}

#Preview("Related controls", traits: .shoppingDraft) {
    Form {
        ShoppingControlGroup {
            Text("What would you like to add?")
                .font(.title2)
            Button("Dictate", systemImage: "mic") {}
                .labelStyle(.iconOnly)
                .buttonStyle(ShoppingIconButtonStyle())
        }
    }
    .modifier(ShoppingFormStyle())
}
