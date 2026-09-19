import SwiftUI

struct SharedInvitationsView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: SharedShoppingViewModel

    var body: some View {
        NavigationStack {
            Form {
                SharedOperationSection(viewModel: viewModel)
                Section {
                    Button("Crear invitación", systemImage: "link") {
                        Task {
                            await viewModel.createInvitation()
                        }
                    }
                    .disabled(!viewModel.canMutate || !viewModel.isCreator)
                    if let url = viewModel.shareURL {
                        ShareLink(item: url) {
                            Label("Compartir invitación", systemImage: "square.and.arrow.up")
                        }
                    }
                } header: {
                    Text("Nuevo enlace")
                } footer: {
                    Text("Cada enlace permite que una persona se una durante 24 horas. Compártelo ahora: el enlace no se recupera al volver a abrir la app.")
                }
                Section("Invitaciones creadas") {
                    if viewModel.invitations.isEmpty {
                        Text("No hay invitaciones cargadas.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.invitations) { invitation in
                        VStack(alignment: .leading) {
                            VStack(alignment: .leading) {
                                Text("Creada el \(invitation.createdAt, format: .dateTime.day().month().year().hour().minute().second())")
                                Text("Vence el \(invitation.expiresAt, format: .dateTime.day().month().year().hour().minute())")
                                    .foregroundStyle(.secondary)
                                if invitation.acceptedAt != nil {
                                    Label("Aceptada", systemImage: "person.crop.circle.badge.checkmark")
                                } else if invitation.revokedAt != nil {
                                    Label("Revocada", systemImage: "xmark.circle")
                                } else {
                                    Text("Sin aceptar")
                                }
                            }
                            .accessibilityElement(children: .combine)
                            if invitation.acceptedAt == nil && invitation.revokedAt == nil {
                                Button("Revocar enlace", role: .destructive) {
                                    Task {
                                        await viewModel.revokeInvitation(invitation)
                                    }
                                }
                                .disabled(!viewModel.canMutate || !viewModel.isCreator)
                                .accessibilityHint("Impide que alguien utilice esta invitación para unirse al grupo.")
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle("Invitaciones")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview("Invitaciones del grupo", traits: .sharedShopping(.invitations)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedInvitationsView(viewModel: viewModel)
}

#Preview("Invitaciones con texto grande", traits: .sharedShopping(.invitations)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedInvitationsView(viewModel: viewModel)
        .environment(\.dynamicTypeSize, .accessibility5)
}
