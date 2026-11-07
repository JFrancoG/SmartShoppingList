import SwiftUI

struct AppPreparationView: View {
    let state: AppBootstrap.State
    let retry: () -> Void
    var cancel: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if case .recovery = state {
                    ContentUnavailableView {
                        Label("Unable to prepare the app", systemImage: "exclamationmark.icloud")
                    } description: {
                        Text("We could not verify this installation. Check your connection and try again. Your saved data is preserved.")
                    } actions: {
                        Button("Try again") {
                            retry()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView("Preparing the app…")
                    Text("Verifying this installation before opening your account and lists.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Cancel") {
                        cancel()
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .contentMargins(.vertical, 48)
    }
}

#Preview("Preparing") {
    AppPreparationView(state: .resolving, retry: {})
}

#Preview("Recovery") {
    AppPreparationView(state: .recovery(.unavailable), retry: {})
}
