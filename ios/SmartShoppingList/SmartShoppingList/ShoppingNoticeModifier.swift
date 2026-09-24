import SwiftUI

/// Uses the system presentation for viewport-independent visibility and accessible alert focus.
struct ShoppingNoticeModifier: ViewModifier {
    let notice: ShoppingNotice?
    var isEnabled = true
    let dismiss: @MainActor @Sendable (ShoppingNotice) -> Void
    @State private var presentedNotice: ShoppingNotice?
    @State private var isPresented = false
    @State private var acknowledgedNotice: ShoppingNotice?

    func body(content: Content) -> some View {
        content
            .alert(
                Text(presentedNotice?.title ?? "Shopping list notice"),
                isPresented: $isPresented,
                presenting: presentedNotice
            ) { snapshot in
                Button("Dismiss notice", role: .cancel) {
                    acknowledgedNotice = snapshot
                    dismiss(snapshot)
                }
            } message: { snapshot in
                Text(snapshot.message)
            }
            .onChange(of: notice, initial: true) { _, _ in
                acknowledgedNotice = nil
                presentIfPossible()
            }
            .onChange(of: isEnabled) { _, _ in
                if isEnabled {
                    presentIfPossible()
                } else {
                    isPresented = false
                }
            }
            .onChange(of: isPresented) { _, presented in
                if !presented {
                    presentedNotice = nil
                    presentIfPossible()
                }
            }
    }

    private func presentIfPossible() {
        guard isEnabled, !isPresented, let notice, notice != acknowledgedNotice else { return }
        presentedNotice = notice
        isPresented = true
    }
}

#Preview("Aviso largo · AX5") {
    Color.clear
        .modifier(ShoppingNoticeModifier(
            notice: ShoppingNotice(
                source: .storage,
                message: "The saved draft could not be restored. It is kept unchanged. Changes in this session will not be saved when you close the app."
            ),
            dismiss: { _ in }
        ))
        .environment(\.dynamicTypeSize, .accessibility5)
}
