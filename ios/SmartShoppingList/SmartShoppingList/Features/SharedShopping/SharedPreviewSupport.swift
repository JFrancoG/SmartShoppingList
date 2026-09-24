import DeveloperToolsSupport
import SwiftUI

struct SharedPreviewModifier: PreviewModifier {
    let state: SharedPreviewState

    static func makeSharedContext() async throws -> SharedPreviewContext {
        let fixture = try SharedPreviewFixture.sample()
        var presentations: [SharedPreviewState: SharedPreviewPresentation] = [:]
        for state in SharedPreviewState.allCases {
            let model = SharedPreviewSupport.viewModel(fixture: fixture, state: state)
            await SharedPreviewSupport.prepare(model, fixture: fixture, state: state)
            presentations[state] = SharedPreviewPresentation(model: model, fixture: fixture, state: state)
        }
        return SharedPreviewContext(fixture: fixture, presentations: presentations)
    }

    func body(content: Content, context: SharedPreviewContext) -> some View {
        SharedPreviewContainer(context: context, state: state) { viewModel in
            content
                .environment(viewModel)
                .environment(\.locale, Locale(identifier: "es_ES"))
        }
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var sharedShopping: Self { sharedShopping(.group) }

    static func sharedShopping(_ state: SharedPreviewState) -> Self {
        .modifier(SharedPreviewModifier(state: state))
    }
}

enum SharedPreviewState: CaseIterable, Hashable {
    case group
    case signedOut
    case invitation
    case review
    case invitations
    case pending
    case unconfigured
}

/// Cached by Xcode: values only. Each preview creates its own mutable ViewModel and fake services.
struct SharedPreviewContext {
    let fixture: SharedPreviewFixture
    let presentations: [SharedPreviewState: SharedPreviewPresentation]
}

struct SharedPreviewPresentation {
    let session: SharedSession?
    let pendingInvitation: PendingInvitation?
    let invitationPreview: InvitationPreview?
    let pendingOperation: PendingSharedOperation?
    let stores: [SharedStore]
    let items: [SharedItem]
    let invitations: [SharedInvitation]
    let shareURL: URL?
    let sessionIsVerified: Bool
    let notice: LocalizedStringResource?
    let reviewedItems: [PreparedDraftItem]
    let storeChoices: [DraftStoreChoice]
    let selectedStoreID: UUID?
    let isReviewPresented: Bool
    let isInvitationsPresented: Bool
    let reviewSnapshot: ShoppingDraftSnapshot?
}

extension SharedPreviewPresentation {
    @MainActor
    init(model: SharedShoppingViewModel, fixture: SharedPreviewFixture, state: SharedPreviewState) {
        session = model.session
        pendingInvitation = model.pendingInvitation
        invitationPreview = model.invitationPreview
        pendingOperation = model.pendingOperation
        stores = model.stores
        items = model.items
        invitations = model.invitations
        shareURL = model.shareURL
        sessionIsVerified = model.sessionIsVerified
        notice = model.notice
        reviewedItems = model.reviewedItems
        storeChoices = model.storeChoices
        selectedStoreID = model.selectedStoreID
        isReviewPresented = model.isReviewPresented
        isInvitationsPresented = model.isInvitationsPresented
        reviewSnapshot = state == .review ? fixture.draft : nil
    }
}

/// Only these immutable values are shared between previews; each container creates its own models and services.
struct SharedPreviewFixture {
    let configuration: SharedAPIConfiguration
    let session: SharedSession
    let group: SharedGroup
    let stores: [SharedStore]
    let items: [SharedItem]
    let draft: ShoppingDraftSnapshot
    let invitation: SharedInvitation
    let pendingInvitation: PendingInvitation
    let createdInvitation: CreatedInvitation

    static func sample() throws -> SharedPreviewFixture {
        let configuration = try SharedAPIConfiguration(baseURL: "https://api.test", invitationOrigin: "https://links.test")
        let userID = identifier(1)
        let groupID = identifier(16)
        let date = Date(timeIntervalSince1970: 1_789_812_000)
        let group = SharedGroup(
            id: groupID,
            name: "Casa",
            creatorUserId: userID,
            createdAt: date
        )
        let session = SharedSession(
            accessToken: "SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSQ",
            tokenType: "Bearer",
            expiresAt: date.addingTimeInterval(30 * 86_400),
            user: SharedUser(id: userID, displayName: "Alex", group: group)
        )
        let stores = [
            SharedStore(id: identifier(32), groupId: groupID, name: "Mercadona Centro"),
            SharedStore(id: identifier(33), groupId: groupID, name: "Día Norte")
        ]
        let draft = ShoppingDraftSnapshot(
            text: "Leche sin lactosa y pan integral en Mercadona Centro",
            items: [
                ShoppingDraftItem(
                    id: identifier(48),
                    name: "Leche sin lactosa",
                    quantity: "2 briks",
                    store: "Mercadona Centro"
                ),
                ShoppingDraftItem(
                    id: identifier(49),
                    name: "Pan integral de semillas",
                    quantity: "",
                    store: "Mercadona Centro"
                )
            ]
        )
        let items = draft.items.map { entry in
            SharedItem(
                id: entry.id,
                groupId: groupID,
                storeId: identifier(32),
                name: entry.name,
                quantity: entry.quantity.isEmpty ? nil : entry.quantity,
                status: "pending",
                version: 1,
                createdBy: userID,
                createdAt: date,
                purchasedBy: nil,
                purchasedAt: nil
            )
        }
        let invitation = SharedInvitation(
            id: identifier(64),
            groupId: groupID,
            createdAt: date,
            expiresAt: date.addingTimeInterval(86_400),
            revokedAt: nil,
            acceptedAt: nil,
            acceptedBy: nil
        )
        let pendingInvitation = PendingInvitation(
            id: invitation.id,
            token: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        )
        let endpoint = configuration.invitationOrigin.appending(path: "invite/\(invitation.id.uuidString.lowercased())")
        guard var link = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw SharedAPIError.configuration
        }
        link.fragment = "token=\(pendingInvitation.token)"
        guard let invitationURL = link.url else { throw SharedAPIError.configuration }
        return SharedPreviewFixture(
            configuration: configuration,
            session: session,
            group: group,
            stores: stores,
            items: items,
            draft: draft,
            invitation: invitation,
            pendingInvitation: pendingInvitation,
            createdInvitation: CreatedInvitation(invitation: invitation, url: invitationURL)
        )
    }

    private static func identifier(_ suffix: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0, 0, suffix))
    }
}

@MainActor
enum SharedPreviewSupport {
    static func viewModel(
        fixture: SharedPreviewFixture,
        state: SharedPreviewState,
        presentation: SharedPreviewPresentation? = nil
    ) -> SharedShoppingViewModel {
        let draft = DraftPreviewSupport.viewModel(snapshot: fixture.draft, state: .content)
        var session = fixture.session
        if state == .invitation {
            session.user.group = nil
        }
        let pending: PendingSharedOperation? = state == .pending ? .addItems(
            userID: session.user.id,
            groupID: fixture.group.id,
            request: AddItemsRequest(
                operationId: fixture.invitation.id,
                items: fixture.draft.items.map { item in
                    SharedNewItem(
                        name: item.name,
                        quantity: item.quantity.isEmpty ? nil : item.quantity,
                        store: .existing(fixture.stores[0].id)
                    )
                }
            ),
            sourceDraft: fixture.draft
        ) : nil
        let credentials = MemorySharedCredentialStore(
            session: state == .signedOut || state == .unconfigured ? nil : session,
            invitation: state == .invitation || state == .signedOut ? fixture.pendingInvitation : nil,
            operation: pending
        )
        let api = state == .unconfigured ? nil : PreviewSharedShoppingAPI(fixture: fixture, user: session.user)
        let configuration = state == .unconfigured ? nil : fixture.configuration
        #if DEBUG
        if let presentation {
            return SharedShoppingViewModel(
                preview: presentation,
                api: api,
                configuration: configuration,
                credentials: credentials,
                draft: draft
            )
        }
        #endif
        return SharedShoppingViewModel(
            api: api,
            configuration: configuration,
            credentials: credentials,
            draft: draft
        )
    }

    static func prepare(
        _ model: SharedShoppingViewModel,
        fixture: SharedPreviewFixture,
        state: SharedPreviewState
    ) async {
        await model.load()
        switch state {
        case .group:
            model.selectedStoreID = fixture.stores.first?.id
            await model.loadSelectedStore()
        case .review:
            await model.prepareReview()
        case .invitations:
            await model.openInvitations()
            await model.createInvitation()
        case .signedOut, .invitation, .pending, .unconfigured:
            break
        }
    }
}

@MainActor
private struct PreviewSharedShoppingAPI: SharedShoppingAPI {
    let fixture: SharedPreviewFixture
    let user: SharedUser

    // Preview actions never initiate native Apple authorization or perform remote mutations.
    func createChallenge() async throws -> SharedChallenge { throw SharedAPIError.configuration }
    func loginWithApple(_ request: AppleLoginRequest) async throws -> SharedSession { throw SharedAPIError.configuration }
    func currentUser(token: String) async throws -> SharedUser { user }
    func logout(token: String) async throws {}
    func createGroup(_ request: CreateGroupRequest, token: String) async throws -> SharedGroup {
        throw SharedAPIError.configuration
    }
    func stores(groupID: UUID, token: String) async throws -> [SharedStore] { fixture.stores }
    func createInvitation(groupID: UUID, token: String) async throws -> CreatedInvitation {
        fixture.createdInvitation
    }
    func invitations(groupID: UUID, token: String) async throws -> [SharedInvitation] { [fixture.invitation] }
    func revokeInvitation(groupID: UUID, invitationID: UUID, token: String) async throws {
        throw SharedAPIError.configuration
    }
    func previewInvitation(_ invitation: PendingInvitation, token: String) async throws -> InvitationPreview {
        InvitationPreview(group: fixture.group, expiresAt: fixture.invitation.expiresAt, alreadyAccepted: false)
    }
    func acceptInvitation(_ invitation: PendingInvitation, token: String) async throws -> SharedGroup {
        throw SharedAPIError.configuration
    }
    func addItems(_ request: AddItemsRequest, groupID: UUID, token: String) async throws -> [SharedItem] {
        throw SharedAPIError.transport
    }
    func pendingItems(groupID: UUID, storeID: UUID, token: String) async throws -> [SharedItem] {
        fixture.items.filter { $0.storeId == storeID }
    }
}
