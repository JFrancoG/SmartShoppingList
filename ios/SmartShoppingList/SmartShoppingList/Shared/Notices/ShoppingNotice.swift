import Foundation

/// A snapshot of a message, so dismissing an older alert cannot clear a newer result.
struct ShoppingNotice: Equatable {
    enum Source {
        case draft, storage, editor, group, draftConfirmation
    }

    struct StoreDestination: Equatable {
        let operationID: UUID
        let userID: UUID
        let groupID: UUID
        let storeID: UUID
    }

    struct DraftConfirmation: Equatable {
        let proposalID: UUID
        let userID: UUID
        let groupID: UUID
    }

    let source: Source
    let message: LocalizedStringResource
    var storeDestination: StoreDestination?
    var draftConfirmation: DraftConfirmation?

    var title: LocalizedStringResource {
        switch source {
        case .editor: "Check this product"
        case .storage: "Draft storage"
        case .draftConfirmation: "Confirm products"
        case .draft, .group: "Shopping list notice"
        }
    }
}
