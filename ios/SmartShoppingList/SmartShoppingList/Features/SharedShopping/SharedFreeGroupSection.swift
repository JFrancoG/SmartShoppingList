import SwiftUI

struct SharedFreeGroupSection: View {
    let viewModel: SharedShoppingViewModel
    @State private var proposedGroup: SharedGroup?
    @State private var confirmsChange = false

    var body: some View {
        if let access = viewModel.membershipAccess {
            Section {
                LabeledContent("Free group") {
                    Text(viewModel.freeGroupName ?? String(localized: "No group selected"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !access.premiumActive, let transition = access.transitionEndsAt {
                    LabeledContent("Group transition ends") {
                        Text(transition, format: .dateTime.day().month().year().hour().minute())
                    }
                }
                if let nextChange = access.freeGroupChangeAvailableAt {
                    LabeledContent("Next free group change") {
                        Text(nextChange, format: .dateTime.day().month().year().hour().minute())
                    }
                }
                ForEach(viewModel.groups) { group in
                    if group.id != access.freeGroupId {
                        Button {
                            proposedGroup = group
                            confirmsChange = true
                        } label: {
                            Label {
                                Text("Use \(group.name) as free group")
                                    .fixedSize(horizontal: false, vertical: true)
                                if viewModel.groupNeedsIdentifier(group) {
                                    Text(group.id.uuidString).font(.caption)
                                }
                            } icon: {
                                Image(systemName: "person.2.badge.gearshape")
                            }
                        }
                        .disabled(!viewModel.canSelectFreeGroup)
                        .accessibilityHint("Changes the account's free group on all devices. Your active shopping group stays selected.")
                    }
                }
            } header: {
                Text("Free group")
            } footer: {
                Text("Choose one group for full use without premium. You can change it once every 30 days. Leaving or closing it allows a replacement. Your other memberships and data are kept.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Color.surface)
            .confirmationDialog(
                "Change free group?",
                isPresented: $confirmsChange,
                presenting: proposedGroup
            ) { group in
                Button("Use \(group.name) as free group") {
                    Task {
                        await viewModel.selectFreeGroup(id: group.id)
                    }
                }
            } message: { group in
                Text("\(viewModel.groupConfirmationName(group)) will be your free group on all devices. Ordinary changes follow a 30-day limit; replacing a group keeps the previous change schedule. No membership or content is removed.")
            }
        }
    }
}

#Preview("Free group · ES", traits: .sharedShopping(.premiumTransition)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        Form {
            SharedFreeGroupSection(viewModel: viewModel)
        }
    }
    .environment(\.locale, Locale(identifier: "es"))
}

#Preview("Free group · EN AX5", traits: .sharedShopping(.premiumRestricted)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        Form {
            SharedFreeGroupSection(viewModel: viewModel)
        }
    }
    .environment(\.locale, Locale(identifier: "en"))
    .environment(\.dynamicTypeSize, .accessibility5)
}
