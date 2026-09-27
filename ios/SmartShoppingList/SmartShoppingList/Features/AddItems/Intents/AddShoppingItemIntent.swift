import AppIntents
import Foundation

struct AddShoppingItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Add product to shopping list"
    static let description = IntentDescription(
        "Adds a product to a known store in your shared list, or saves it in your draft for review."
    )
    static let supportedModes: IntentModes = .foreground
    static let allowedExecutionTargets: IntentExecutionTargets = .main
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Product", requestValueDialog: "Which product would you like to add?")
    var product: String

    @Parameter(title: "Quantity", requestValueDialog: "What quantity would you like?")
    var quantity: String

    @Parameter(title: "Store", requestValueDialog: "At which store?")
    var store: String

    @Dependency private var shopping: SharedShoppingViewModel

    // The pending server operation and local receipt keep the same identity for this request.
    private let requestID = UUID()

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$product), quantity \(\.$quantity), at \(\.$store) to my list")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome: ShoppingIntentOutcome
        do {
            outcome = try await shopping.addShoppingItemFromIntent(
                ShoppingDraftItem(
                    id: requestID,
                    name: product,
                    quantity: quantity,
                    store: store
                )
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            var message: LocalizedStringResource
            if error is ShoppingIntentError {
                message = "Open the app to check and complete this request before trying again."
            } else {
                message = DraftIntentError.message(for: error)
            }
            message.locale = systemContext.locale
            throw AppIntentError(description: message)
        }

        var message: LocalizedStringResource
        switch outcome {
        case .added(let storeName):
            message = "The product was added to the list for \(storeName)."
        case .savedToDraft:
            message = "The product is saved in your draft. Review it in the app to add it to the group."
        case .alreadyProcessed:
            message = "This request was already processed. Review its status in the app before trying again."
        }
        message.locale = systemContext.locale
        return .result(dialog: IntentDialog(message))
    }
}
