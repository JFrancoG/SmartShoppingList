import SwiftUI

/// Uses the global native accent without a custom tint on the alert's actions.
private struct ShoppingAlertModifier<Data, Actions: View, Message: View>: ViewModifier {
    let title: Text
    @Binding var isPresented: Bool
    let data: Data?
    @ViewBuilder let actions: (Data) -> Actions
    @ViewBuilder let message: (Data) -> Message

    func body(content: Content) -> some View {
        content.background {
            Color.clear
                .tint(nil)
                .alert(title, isPresented: $isPresented, presenting: data, actions: actions, message: message)
        }
    }
}

extension View {
    func shoppingAlert<Data, Actions: View, Message: View>(
        _ title: Text,
        isPresented: Binding<Bool>,
        presenting data: Data?,
        @ViewBuilder actions: @escaping (Data) -> Actions,
        @ViewBuilder message: @escaping (Data) -> Message
    ) -> some View {
        modifier(ShoppingAlertModifier(
            title: title,
            isPresented: isPresented,
            data: data,
            actions: actions,
            message: message
        ))
    }

    func shoppingAlert<Actions: View, Message: View>(
        _ title: Text,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder message: @escaping () -> Message
    ) -> some View {
        shoppingAlert(title, isPresented: isPresented, presenting: ()) { _ in
            actions()
        } message: { _ in
            message()
        }
    }
}
