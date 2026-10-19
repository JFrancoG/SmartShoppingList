import SwiftUI

/// Shared action hierarchy; the native alert owns layout, dismissal and accessibility focus.
struct ShoppingAlertActions: View {
    let primaryTitle: Text
    var primaryRole: ButtonRole? = nil
    var secondaryTitle: Text? = Text("Cancel")
    let confirm: () -> Void
    var cancel: () -> Void = {}

    var body: some View {
        Button(role: primaryRole, action: confirm) {
            primaryTitle
        }
        // Destructive confirmations require an explicit choice, not the Return key's default action.
        .keyboardShortcut(primaryRole == .destructive ? nil : .defaultAction)
        if let secondaryTitle {
            Button(role: .cancel, action: cancel) {
                secondaryTitle
            }
        }
    }
}

#Preview("Archive confirmation · ES", traits: .sharedShopping) {
    @Previewable @State var isPresented = true
    Color.canvas
        .shoppingAlert(Text("Archive store?"), isPresented: $isPresented) {
            ShoppingAlertActions(primaryTitle: Text("Archive")) {} cancel: {}
        } message: {
            Text("Archive \("T4")? It will stop appearing in shopping lists and will keep its history.")
        }
        .environment(\.locale, Locale(identifier: "es"))
}

#Preview("Single notice · ES", traits: .sharedShopping) {
    @Previewable @State var isPresented = true
    Color.canvas
        .shoppingAlert(Text("Smart List"), isPresented: $isPresented) {
            ShoppingAlertActions(primaryTitle: Text("OK"), secondaryTitle: nil) {} cancel: {}
        } message: {
            Text("No products were found. You can rephrase the text or add them manually.")
        }
        .environment(\.locale, Locale(identifier: "es"))
}

#Preview("Destructive confirmation · ES", traits: .sharedShopping) {
    @Previewable @State var isPresented = true
    Color.canvas
        .shoppingAlert(Text("Close group and leave?"), isPresented: $isPresented) {
            ShoppingAlertActions(primaryTitle: Text("Close group and leave"), primaryRole: .destructive) {} cancel: {}
        } message: {
            Text("You are the last member. The group will close and its invitations will stop working. Its history is preserved, but reopening is not available.")
        }
        .environment(\.locale, Locale(identifier: "es"))
}
