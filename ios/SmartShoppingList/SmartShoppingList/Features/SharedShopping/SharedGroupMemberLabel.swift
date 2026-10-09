import SwiftUI

struct SharedGroupMemberLabel: View {
    @ScaledMetric(relativeTo: .body) private var labelSpacing = 4.0
    let member: SharedGroupMember
    let isCurrentUser: Bool
    let isAdministrator: Bool
    let showsIdentifier: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: labelSpacing) {
            if let name = member.visibleName {
                Text(name)
            } else {
                Text("Unnamed member")
            }
            if isCurrentUser {
                Text("You")
                    .foregroundStyle(.textSecondary)
            }
            if isAdministrator {
                Text("Administrator")
                    .foregroundStyle(.textSecondary)
            }
            if showsIdentifier {
                Text("Member ID: \(member.id.uuidString.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
                    .textSelection(.enabled)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Members · ES", traits: .sharedShopping(.groupManagementOwner)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        ForEach(viewModel.groupMembers) { member in
            SharedGroupMemberLabel(
                member: member,
                isCurrentUser: member.id == viewModel.session?.user.id,
                isAdministrator: member.id == viewModel.group?.administratorUserId,
                showsIdentifier: viewModel.memberNeedsIdentifier(member)
            )
        }
    }
    .environment(\.locale, Locale(identifier: "es"))
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Members · EN", traits: .sharedShopping(.groupManagementOwner)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        ForEach(viewModel.groupMembers) { member in
            SharedGroupMemberLabel(
                member: member,
                isCurrentUser: member.id == viewModel.session?.user.id,
                isAdministrator: member.id == viewModel.group?.administratorUserId,
                showsIdentifier: viewModel.memberNeedsIdentifier(member)
            )
        }
    }
    .environment(\.locale, Locale(identifier: "en"))
    .environment(\.dynamicTypeSize, .large)
}
