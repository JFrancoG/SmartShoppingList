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
                if let snapshot = presentedNotice {
                    Color.clear
                        .alert(
                            Text(snapshot.title),
                            isPresented: presentationBinding(for: currentPresentationID),
                            presenting: snapshot
                        ) { shownNotice in
                            Button("Dismiss notice", role: .cancel) {
                                guard currentPresentationID == presentationID else { return }
                                acknowledgedNotice = shownNotice
                                dismiss(shownNotice)
                            }
                        } message: { shownNotice in
                            Text(shownNotice.message)
                        }
                        .id(currentPresentationID)
                }
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
                    // Keep the closing host's content until the next presentation replaces it.
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
