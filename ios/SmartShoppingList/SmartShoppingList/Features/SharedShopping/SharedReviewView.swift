import SwiftUI

struct SharedReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SharedShoppingViewModel

    var body: some View {
        NavigationStack {
            Form {
                SharedOperationSection(viewModel: viewModel)
                Section {
                    ForEach(viewModel.reviewedItems) { item in
                        VStack(alignment: .leading) {
                            Text(item.name)
                                .font(.headline)
                            if let quantity = item.quantity {
                                Text(quantity)
                            }
                            Text("Specified store: \(item.store)")
                                .foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Reviewed products · \(viewModel.reviewedItems.count)")
                } footer: {
                    Text("To correct products or quantities, return to the draft before confirming.")
                }
                Section {
                    ForEach($viewModel.storeChoices) { $choice in
                        Picker("Store for “\(choice.id)”", selection: $choice.selection) {
                            Text("Select an option").tag("")
                            Text("Confirm the name “\(choice.id)”").tag("new")
                            ForEach(viewModel.stores) { store in
                                Text(store.name).tag(store.id.uuidString)
                            }
                        }
                        .pickerStyle(.navigationLink)
                        .disabled(viewModel.isBusy)
                        .accessibilityHint("Choose a store from the group or confirm the name you reviewed.")
                    }
                } header: {
                    Text("Confirm stores")
                } footer: {
                    Text("Confirm an option for each name. If that name already exists in the group, the same store will be used.")
                }
                Section {
                    Button("Confirm adding to group", systemImage: "plus.circle") {
                        Task {
                            await viewModel.confirmReviewedBatch()
                        }
                    }
                    .disabled(!viewModel.canConfirmReview)
                    .accessibilityHint("Adds all reviewed products to the group with the chosen stores.")
                } footer: {
                    Text("Products will only be shared when you confirm this submission.")
                }
            }
            .navigationTitle("Review submission")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back", role: .cancel) {
                        dismiss()
                    }
                    .disabled(viewModel.isBusy)
                }
            }
            .interactiveDismissDisabled(viewModel.isBusy)
        }
        .modifier(ShoppingNoticeModifier(
            notice: viewModel.presentedNotice,
            isEnabled: viewModel.isReviewPresented,
            dismiss: viewModel.dismissPresentedNotice
        ))
    }
}

#Preview("Elegir tiendas", traits: .sharedShopping(.review)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedReviewView(viewModel: viewModel)
}

#Preview("Revisión con texto grande", traits: .sharedShopping(.review)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedReviewView(viewModel: viewModel)
        .environment(\.dynamicTypeSize, .accessibility5)
}
