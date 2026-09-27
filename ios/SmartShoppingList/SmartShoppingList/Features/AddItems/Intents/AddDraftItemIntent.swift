import AppIntents
import Foundation

struct AddDraftItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Add product to draft"
    static let description = IntentDescription(
        "Adds a product to the local draft for review before sharing it with the group."
    )
    static let supportedModes: IntentModes = .foreground
    static let allowedExecutionTargets: IntentExecutionTargets = .main
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Product", requestValueDialog: "Which product would you like to add?")
    var product: String

    @Parameter(title: "Store", requestValueDialog: "At which store?")
    var store: String

    @Parameter(title: "Quantity")
    var quantity: String?

    @Dependency private var shopping: SharedShoppingViewModel

    // Copies of this intent share an identity; a new system invocation creates a new one.
    private let requestID = UUID()

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$product) at \(\.$store) to the draft") {
            \.$quantity
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let added: Bool
        do {
            added = try await shopping.addDraftItemFromIntent(
                ShoppingDraftItem(
                    id: requestID,
                    name: product,
                    quantity: quantity ?? "",
                    store: store
                )
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            var message = DraftIntentError.message(for: error)
            message.locale = systemContext.locale
            throw AppIntentError(description: message)
        }

        var message: LocalizedStringResource = added
            ? "The product is saved in your draft. Review it in the app before adding it to the group."
            : "This request was already processed. No duplicate product was added. Review your draft in the app."
        message.locale = systemContext.locale
        return .result(dialog: IntentDialog(message))
    }
}
