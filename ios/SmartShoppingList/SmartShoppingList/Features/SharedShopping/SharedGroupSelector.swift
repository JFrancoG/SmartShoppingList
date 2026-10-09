import SwiftUI

struct SharedGroupSelector: View {
    let viewModel: SharedShoppingViewModel

    var body: some View {
        if !viewModel.groups.isEmpty {
            Section {
                Picker("Active group", selection: Binding(
                    get: { viewModel.group?.id },
                    set: { groupID in
                        guard let groupID else { return }
                        Task {
                            await viewModel.selectGroup(id: groupID)
                        }
                    }
                )) {
                    if viewModel.group == nil {
                        Text("Select a group").tag(Optional<UUID>.none)
                    }
                    ForEach(viewModel.groups) { group in
                        VStack(alignment: .leading) {
                            Text(group.name)
                            if viewModel.groupNeedsIdentifier(group) {
                                Text(group.id.uuidString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                        .tag(Optional(group.id))
                    }
                }
                .pickerStyle(.navigationLink)
                .disabled(!viewModel.canSelectGroup)
                .accessibilityHint("Choose the group for shopping and new submissions. Your local draft is kept.")
            } footer: {
                if viewModel.pendingOperation != nil {
                    Text("Resolve the saved submission before changing groups. It keeps its original destination.")
                } else if viewModel.group == nil {
                    Text("Choose a group before sharing products. Your local draft has no destination yet.")
                }
            }
            .listRowBackground(Color.surface)
        }
    }
}

#Preview("Groups · ES", traits: .sharedShopping(.multipleGroups)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        Form {
            SharedGroupSelector(viewModel: viewModel)
        }
    }
    .environment(\.locale, Locale(identifier: "es"))
}

#Preview("Groups · EN AX5", traits: .sharedShopping(.multipleGroups)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        Form {
            SharedGroupSelector(viewModel: viewModel)
        }
    }
    .environment(\.locale, Locale(identifier: "en"))
    .environment(\.dynamicTypeSize, .accessibility5)
}
