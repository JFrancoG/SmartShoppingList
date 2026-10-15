import SwiftUI

struct SharedFreeGroupSection: View {
    @ScaledMetric(relativeTo: .body) private var choiceSpacing = 12.0
    @ScaledMetric(relativeTo: .footnote) private var footerSpacing = 8.0
    let viewModel: SharedShoppingViewModel
    @State private var proposedGroup: SharedGroup?
    @State private var confirmsChange = false

    var date = Date()

    var body: some View {
        switch viewModel.freeGroupPresentation(at: date) {
        case .loading:
            Section {
                ProgressView("Loading your groups…")
            }
            .listRowBackground(Color.surface)
        case .unavailable:
            Section {
                Text("Your groups could not be verified. Refresh to see your free group.")
                Button("Refresh") {
                    Task {
                        await viewModel.refresh()
                    }
                }
                .buttonStyle(ShoppingActionButtonStyle(widthFraction: 1, minimumHeight: 48, usesCapsule: true))
                .disabled(viewModel.isBusy)
            }
            .listRowBackground(Color.surface)
        case .empty:
            Section {
                Text("You have no groups yet")
                    .font(.headline)
                Text("Create a group or accept an invitation from Settings. With the free plan you can use one group.")
            }
            .listRowBackground(Color.surface)
        case .single(let group):
            Section {
                Text(group.name).font(.headline)
                Text("This is your only group. You do not need to choose: it is your group for use with the free plan.")
            }
            .listRowBackground(Color.surface)
        case let .multiple(selected, premiumActive, transitionEnd, nextChange, alternatives):
            Section {
                if let selected {
                    VStack(alignment: .leading) {
                        Text("Your free group: \(viewModel.groupConfirmationName(selected))")
                            .font(.headline)
                        if viewModel.groupNeedsIdentifier(selected) {
                            Text("Created \(selected.createdAt, format: .dateTime.day().month().year().hour().minute())")
                                .font(.subheadline)
                                .foregroundStyle(.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Text("Choose your free group").font(.headline)
                }
                if premiumActive {
                    Text("Premium gives you access to all your groups. Choose which one to keep using if your subscription ends.")
                } else if let transitionEnd {
                    Text("Premium has ended. You can keep shopping in your existing groups until \(transitionEnd, format: .dateTime.day().month(.wide).year().hour().minute()).")
                    Text("After that, you can shop in your free group. Your other groups and their data remain available to consult.")
                    Text("Store and product limits already follow each administrator’s current plan.")
                        .foregroundStyle(.textSecondary)
                } else {
                    Text("With the free plan you can shop in your free group. Your other groups and their data remain available to consult.")
                }
                if selected == nil {
                    Text("If you do not choose, we keep your previous valid choice or use the group you joined first.")
                        .foregroundStyle(.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .listRowBackground(Color.surface)

            Section {
                ForEach(alternatives) { group in
                    VStack(alignment: .leading, spacing: choiceSpacing) {
                        VStack(alignment: .leading) {
                            Text(viewModel.groupConfirmationName(group)).font(.headline)
                            if viewModel.groupNeedsIdentifier(group) {
                                Text("Created \(group.createdAt, format: .dateTime.day().month().year().hour().minute())")
                                    .font(.subheadline)
                                    .foregroundStyle(.textSecondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        Button {
                            proposedGroup = group
                            confirmsChange = true
                        } label: {
                            Text("Choose as free group")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .buttonStyle(ShoppingActionButtonStyle(
                            widthFraction: 1,
                            minimumHeight: 48,
                            isProminent: false,
                            usesCapsule: true
                        ))
                        .disabled(!viewModel.canSelectFreeGroup)
                        .accessibilityLabel("Choose as free group: \(viewModel.groupConfirmationName(group))")
                        .accessibilityHint("Changes the account's free group on all devices. Your active shopping group stays selected.")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                if selected != nil {
                    Text("Choose a different group")
                } else {
                    Text("Choose your free group")
                }
            } footer: {
                VStack(alignment: .leading, spacing: footerSpacing) {
                    if let nextChange {
                        Text("You can change your free group again on \(nextChange, format: .dateTime.day().month(.wide).year().hour().minute()).")
                    }
                    Text("You can change your choice once every 30 days. If you leave this group or it closes, you can choose a replacement. Changing your free group does not switch the group you are viewing.")
                }
            }
            .listRowBackground(Color.surface)
            .confirmationDialog(
                "Change free group?",
                isPresented: $confirmsChange,
                presenting: proposedGroup
            ) { group in
                Button("Choose as free group") {
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

#Preview("Duplicate groups · ES", traits: .sharedShopping(.premiumRestricted)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        Form {
            SharedFreeGroupSection(viewModel: viewModel)
        }
        .modifier(ShoppingFormStyle())
    }
    .environment(\.locale, Locale(identifier: "es"))
}
