import AuthenticationServices
import SwiftUI

struct SharedGroupView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var appleButtonHeight = 44.0
    @Bindable var viewModel: SharedShoppingViewModel

    var body: some View {
        NavigationStack {
            Form {
                SharedOperationSection(viewModel: viewModel)

                if !viewModel.isConfigured {
                    Section("Acceso al grupo") {
                        Text("La conexión del grupo todavía no está configurada. Puedes preparar productos en Añadir.")
                    }
                } else if viewModel.session == nil {
                    Section {
                        Text("Accede con Apple para crear un grupo o aceptar una invitación.")
                        Button("Preparar acceso con Apple") {
                            Task {
                                await viewModel.prepareAppleLogin()
                            }
                        }
                        .disabled(!viewModel.hasLoaded || viewModel.isBusy)

                        if viewModel.challenge != nil {
                            SignInWithAppleButton(.signIn) { request in
                                viewModel.configureAppleRequest(request)
                            } onCompletion: { result in
                                viewModel.receiveAppleAuthorization(result)
                            }
                            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                            .frame(height: appleButtonHeight)
                            .disabled(viewModel.isBusy)
                        }
                    } header: {
                        Text("Acceso con Apple")
                    } footer: {
                        Text("Tu borrador y la invitación pendiente se conservan durante el acceso.")
                    }
                }

                if viewModel.pendingInvitation != nil {
                    Section("Invitación pendiente") {
                        if let invitation = viewModel.invitationPreview {
                            VStack(alignment: .leading) {
                                Text(invitation.group.name)
                                    .font(.headline)
                                Text("Vence el \(invitation.expiresAt, format: .dateTime.day().month().year().hour().minute())")
                                    .foregroundStyle(.secondary)
                                if invitation.alreadyAccepted {
                                    Text("Ya has aceptado esta invitación.")
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                            Button("Aceptar invitación", systemImage: "person.badge.plus") {
                                Task {
                                    await viewModel.acceptInvitation()
                                }
                            }
                            .disabled(!viewModel.canMutate)
                        } else {
                            Text("Accede y actualiza para consultar el grupo antes de aceptar.")
                        }
                        Button("Descartar invitación", role: .destructive) {
                            Task {
                                await viewModel.discardInvitation()
                            }
                        }
                        .disabled(viewModel.isBusy)
                    }
                }

                if let session = viewModel.session {
                    if let group = viewModel.group {
                        Section("Tu grupo") {
                            Text(group.name)
                                .font(.headline)
                            if viewModel.isCreator {
                                Button("Gestionar invitaciones", systemImage: "person.badge.plus") {
                                    Task {
                                        await viewModel.openInvitations()
                                    }
                                }
                                .disabled(!viewModel.canMutate)
                            }
                        }
                        Section("Supermercado") {
                            Picker("Tienda", selection: $viewModel.selectedStoreID) {
                                Text("Selecciona una tienda").tag(Optional<UUID>.none)
                                ForEach(viewModel.stores) { store in
                                    Text(store.name).tag(Optional(store.id))
                                }
                            }
                            .pickerStyle(.navigationLink)
                            .disabled(viewModel.isBusy || !viewModel.sessionIsVerified)
                            if viewModel.stores.isEmpty {
                                Text("No hay tiendas cargadas. Puedes confirmar una tienda al incorporar productos.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if viewModel.selectedStoreID != nil {
                            SharedPurchaseSection(viewModel: viewModel)
                        }
                    } else {
                        Section {
                            TextField("Nombre del grupo", text: $viewModel.groupName)
                                .textInputAutocapitalization(.sentences)
                                .disabled(!viewModel.canMutate)
                            Button("Crear grupo", systemImage: "person.2") {
                                Task {
                                    await viewModel.createGroup()
                                }
                            }
                            .disabled(!viewModel.canMutate)
                        } header: {
                            Text("Crear un grupo")
                        } footer: {
                            Text("También puedes abrir una invitación para unirte a otro grupo. Cada cuenta pertenece a un solo grupo.")
                        }
                    }
                    Section("Sesión") {
                        if let name = session.user.displayName {
                            Text(name)
                        }
                        Button("Cerrar sesión") {
                            Task {
                                await viewModel.logout()
                            }
                        }
                        .disabled(viewModel.isBusy)
                    }
                }
            }
            .navigationTitle("Grupo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Actualizar", systemImage: "arrow.clockwise") {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                    .disabled(!viewModel.hasLoaded || viewModel.isBusy || !viewModel.isConfigured)
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task(id: viewModel.selectedStoreID) {
                await viewModel.loadSelectedStore()
            }
            .sheet(isPresented: $viewModel.isInvitationsPresented) {
                SharedInvitationsView(viewModel: viewModel)
            }
        }
    }
}

#Preview("Grupo y productos", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedGroupView(viewModel: viewModel)
}

#Preview("Acceso pendiente", traits: .sharedShopping(.signedOut)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedGroupView(viewModel: viewModel)
}

#Preview("Invitación y texto grande", traits: .sharedShopping(.invitation)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedGroupView(viewModel: viewModel)
        .environment(\.dynamicTypeSize, .accessibility5)
}
