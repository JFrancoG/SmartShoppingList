import SwiftUI

struct SharedRootView: View {
    @State private var selectedTab = SharedTab.add
    @Bindable var viewModel: SharedShoppingViewModel

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Add", systemImage: "plus.circle", value: SharedTab.add) {
                AddItemsView(viewModel: viewModel.draft, shared: viewModel)
            }
            Tab("Shop", systemImage: "cart", value: SharedTab.shop) {
                SharedGroupView(viewModel: viewModel)
            }
        }
        .task {
            await viewModel.load()
        }
        .onOpenURL { url in
            Task {
                await viewModel.receiveInvitation(url)
            }
        }
        .onChange(of: viewModel.pendingInvitation, initial: true) { _, invitation in
            guard invitation != nil else { return }
            selectedTab = .shop
        }
        .sheet(isPresented: $viewModel.isReviewPresented, onDismiss: {
            viewModel.reviewPresentationDidDismiss()
        }) {
            SharedReviewView(viewModel: viewModel)
        }
        .modifier(ShoppingNoticeModifier(
            notice: viewModel.presentedNotice
                ?? (selectedTab == .add ? viewModel.draft.presentedNotice : viewModel.purchaseSelectionNotice),
            isEnabled: viewModel.canPresentRootNotice,
            dismiss: { snapshot in
                viewModel.dismissPresentedNotice(snapshot)
                viewModel.draft.dismissPresentedNotice(snapshot)
            }
        ))
    }

    private enum SharedTab {
        case add
        case shop
    }
}

#Preview(traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedRootView(viewModel: viewModel)
}
