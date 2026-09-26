import SwiftUI

struct SharedRootView: View {
    @State private var selectedTab = SharedTab.add
    @State private var isSettingsPresented = false
    @State private var isSettingsPresentationActive = false
    @State private var settingsPresentationRequested = false
    @Bindable var viewModel: SharedShoppingViewModel

    var body: some View {
        let notice = viewModel.presentedNotice
            ?? (selectedTab == .add ? viewModel.draftConfirmationNotice ?? viewModel.draft.presentedNotice : nil)
        TabView(selection: $selectedTab) {
            Tab("Add", systemImage: "plus.circle", value: SharedTab.add) {
                AddItemsView(viewModel: viewModel.draft, shared: viewModel, onOpenSettings: requestSettings)
            }
            Tab("Shop", systemImage: "cart", value: SharedTab.shop) {
                SharedGroupView(viewModel: viewModel, onOpenSettings: requestSettings)
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
            requestSettings()
        }
        .onChange(of: viewModel.canPresentRootNotice) { _, _ in
            presentSettingsIfPossible()
        }
        .sheet(isPresented: $isSettingsPresented, onDismiss: {
            isSettingsPresentationActive = false
            if selectedTab == .add {
                viewModel.draft.setActive(true)
            }
            presentSettingsIfPossible()
        }) {
            SharedSettingsView(viewModel: viewModel, canPresentNotice: isSettingsPresented)
        }
        .sheet(isPresented: $viewModel.isReviewPresented, onDismiss: {
            viewModel.reviewPresentationDidDismiss()
        }) {
            SharedReviewView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isItemEditorPresented, onDismiss: {
            viewModel.itemEditorPresentationDidDismiss()
        }) {
            SharedItemEditorView(viewModel: viewModel)
        }
        .modifier(ShoppingNoticeModifier(
            notice: notice,
            isEnabled: viewModel.canPresentRootNotice
                && !isSettingsPresentationActive && !settingsPresentationRequested
                && (notice?.draftConfirmation == nil || viewModel.canMutate),
            dismiss: { snapshot in
                viewModel.dismissPresentedNotice(snapshot)
                viewModel.draft.dismissPresentedNotice(snapshot)
            },
            openStore: { snapshot in
                if viewModel.openNoticeStore(snapshot) {
                    selectedTab = .shop
                }
            },
            confirmDraft: { snapshot in
                Task {
                    await viewModel.confirmInterpretationProposal(snapshot)
                }
            },
            editDraft: { snapshot in
                viewModel.editInterpretationProposal(snapshot)
            }
        ))
    }

    private func requestSettings() {
        guard !isSettingsPresented else { return }
        settingsPresentationRequested = true
        viewModel.closeStoreQuery()
        viewModel.draft.setActive(false)
        presentSettingsIfPossible()
    }

    private func presentSettingsIfPossible() {
        guard settingsPresentationRequested,
              !isSettingsPresentationActive,
              viewModel.canPresentRootNotice else {
            return
        }
        settingsPresentationRequested = false
        isSettingsPresentationActive = true
        isSettingsPresented = true
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
