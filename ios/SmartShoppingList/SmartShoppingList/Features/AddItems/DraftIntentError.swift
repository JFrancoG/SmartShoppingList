import Foundation

enum DraftIntentError: Error, Equatable {
    case busy
    case storageUnavailable
    case saveFailed

    @MainActor
    static func message(for error: any Error) -> LocalizedStringResource {
        if let validation = error as? DraftValidationError {
            return ShoppingDraftViewModel.validationMessage(validation)
        }
        switch error as? DraftIntentError {
        case .busy:
            return "The draft is busy. Finish the current edit or operation in the app, then try again."
        case .storageUnavailable:
            return "Your saved data could not be restored. Open the app and resolve the storage problem before adding products."
        case .saveFailed:
            return "The product is in the open draft, but could not be saved. Keep the app open and review it before trying again."
        case .none:
            return "The product could not be added. Open the app and review your draft before trying again."
        }
    }
}
