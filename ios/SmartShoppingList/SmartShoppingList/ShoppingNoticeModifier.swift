import SwiftUI

/// Uses the system presentation for viewport-independent visibility and accessible alert focus.
struct ShoppingNoticeModifier: ViewModifier {
    let notice: ShoppingNotice?
    var isEnabled = true
    let dismiss: @MainActor @Sendable (ShoppingNotice) -> Void
    @State private var presentedNotice: ShoppingNotice?
    @State private var isPresented = false
    @State private var presentationID = UUID()
    @State private var acknowledgedNotice: ShoppingNotice?

    func body(content: Content) -> some View {
        let currentPresentationID = presentationID
        content
            .background {
                Color.clear
                    .alert(
                        Text(presentedNotice?.title ?? "Shopping list notice"),
                        isPresented: presentationBinding(for: currentPresentationID),
                        presenting: presentedNotice
                    ) { snapshot in
                        Button("Dismiss notice", role: .cancel) {
                            guard currentPresentationID == presentationID else { return }
                            acknowledgedNotice = snapshot
                            dismiss(snapshot)
                        }
                    } message: { snapshot in
                        Text(snapshot.message)
                    }
                    .id(presentationID)
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

    private func presentationBinding(for id: UUID) -> Binding<Bool> {
        // A closing alert may write again after the next presentation has started.
        Binding {
            id == presentationID && isPresented
        } set: { presented in
            guard id == presentationID else { return }
            isPresented = presented
        }
    }

    private func presentIfPossible() {
        guard isEnabled, !isPresented, let notice, notice != acknowledgedNotice else { return }
        presentedNotice = notice
        presentationID = UUID()
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
