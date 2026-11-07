import SwiftUI

struct AppBootstrapView: View {
    @State private var isTestDataNoticePresented = false
    @Bindable var bootstrap: AppBootstrap

    var body: some View {
        Group {
            if let shopping = bootstrap.shopping {
                VStack(spacing: 0) {
                    if bootstrap.environment == .sandbox {
                        Button {
                            isTestDataNoticePresented = true
                        } label: {
                            Label("Test data", systemImage: "info.circle")
                                .font(.footnote)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .background(.bar, ignoresSafeAreaEdges: [])
                        .accessibilityHint("Learn how this version keeps test data separate.")
                    }
                    AppRootView(viewModel: shopping.draft, shared: shopping)
                }
            } else {
                AppPreparationView(state: bootstrap.state) {
                    Task {
                        await bootstrap.retry()
                    }
                } cancel: {
                    bootstrap.cancelPreparation()
                }
            }
        }
        .task {
            await bootstrap.prepare()
        }
        .onOpenURL { url in
            Task {
                await bootstrap.receiveInvitation(url)
            }
        }
        .alert("Test data", isPresented: $isTestDataNoticePresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Test data. Lists and purchases stay separate from the App Store version.")
        }
        .alert("Invitation", isPresented: Binding(
            get: { bootstrap.invitationNotice != nil },
            set: { isPresented in
                if !isPresented {
                    bootstrap.invitationNotice = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                bootstrap.invitationNotice = nil
            }
        } message: {
            if let notice = bootstrap.invitationNotice {
                Text(notice)
            }
        }
    }
}

#if DEBUG
#Preview("Sandbox", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var shopping
    AppBootstrapView(bootstrap: AppBootstrap(previewShopping: shopping, environment: .sandbox))
}
#endif
