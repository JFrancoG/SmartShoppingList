import SwiftUI

/// Uses the system presentation for viewport-independent visibility and accessible alert focus.
struct ShoppingNoticeModifier: ViewModifier {
    let notice: ShoppingNotice?
    var isEnabled = true
    let dismiss: @MainActor @Sendable (ShoppingNotice) -> Void
    var openStore: (@MainActor @Sendable (ShoppingNotice) -> Void)?
    var confirmDraft: (@MainActor @Sendable (ShoppingNotice) -> Void)?
    var editDraft: (@MainActor @Sendable (ShoppingNotice) -> Void)?
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
                        .shoppingAlert(
                            Text(snapshot.title),
                            isPresented: presentationBinding(for: currentPresentationID),
                            presenting: snapshot
                        ) { shownNotice in
                            if shownNotice.draftConfirmation != nil, let confirmDraft, let editDraft {
                                ShoppingAlertActions(
                                    primaryTitle: shownNotice.draftConfirmation?.groupName.map { Text("Add to \($0)") }
                                        ?? Text("Confirm"),
                                    secondaryTitle: Text("Edit")
                                ) {
                                    guard currentPresentationID == presentationID else { return }
                                    acknowledgedNotice = shownNotice
                                    confirmDraft(shownNotice)
                                } cancel: {
                                    guard currentPresentationID == presentationID else { return }
                                    acknowledgedNotice = shownNotice
                                    editDraft(shownNotice)
                                }
                            } else {
                                let hasStoreAction = shownNotice.storeDestination != nil && openStore != nil
                                if hasStoreAction, let openStore {
                                    ShoppingAlertActions(
                                        primaryTitle: Text("Open list"),
                                        secondaryTitle: Text("Dismiss notice")
                                    ) {
                                        guard currentPresentationID == presentationID else { return }
                                        acknowledgedNotice = shownNotice
                                        openStore(shownNotice)
                                        dismiss(shownNotice)
                                    } cancel: {
                                        guard currentPresentationID == presentationID else { return }
                                        acknowledgedNotice = shownNotice
                                        dismiss(shownNotice)
                                    }
                                } else {
                                    ShoppingAlertActions(primaryTitle: Text("Dismiss notice"), secondaryTitle: nil) {
                                        guard currentPresentationID == presentationID else { return }
                                        acknowledgedNotice = shownNotice
                                        dismiss(shownNotice)
                                    } cancel: {}
                                }
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
