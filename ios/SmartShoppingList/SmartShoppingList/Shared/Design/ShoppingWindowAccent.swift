import SwiftUI

/// Applies the native accent to this scene's window without tinting SwiftUI alert labels.
struct ShoppingWindowAccent: UIViewRepresentable {
    func makeUIView(context: Context) -> ShoppingWindowAccentView {
        ShoppingWindowAccentView()
    }

    func updateUIView(_ uiView: ShoppingWindowAccentView, context: Context) {}
}
