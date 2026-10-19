#if DEBUG
import StoreKit
import SwiftUI

/// Mounts StoreKit with a real, immutable transaction before requesting presentation.
struct SandboxRefundPresentation: View {
    @Environment(\.usesPreparedShoppingPreview) private var usesPreparedShoppingPreview
    let request: SandboxRefundRequest
    let onDismiss: (SandboxRefundOutcome) -> Void
    @State private var isPresented = false
    @State private var didPresent = false

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .refundRequestSheet(for: request.transactionID, isPresented: $isPresented) { result in
                onDismiss(SandboxRefundOutcome(result))
            }
            .task {
                guard !usesPreparedShoppingPreview, !didPresent, !Task.isCancelled else { return }
                didPresent = true
                isPresented = true
            }
    }
}

#Preview("Refund presentation host", traits: .sharedShopping(.premiumActive)) {
    SandboxRefundPresentation(
        request: SandboxRefundRequest(
            transactionID: 42,
            userID: UUID(uuid: (0, 0, 0, 0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0, 0, 1)),
            accessToken: "preview-only"
        )
    ) { _ in }
}
#endif
