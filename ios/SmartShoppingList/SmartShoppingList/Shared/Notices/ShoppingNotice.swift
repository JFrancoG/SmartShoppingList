import Foundation

/// A snapshot of a message, so dismissing an older alert cannot clear a newer result.
struct ShoppingNotice: Equatable {
    enum Source {
        case draft, storage, editor, group
    }

    let source: Source
    let message: LocalizedStringResource

    var title: LocalizedStringResource {
        switch source {
        case .editor: "Check this product"
        case .storage: "Draft storage"
        case .draft, .group: "Shopping list notice"
        }
    }
}
