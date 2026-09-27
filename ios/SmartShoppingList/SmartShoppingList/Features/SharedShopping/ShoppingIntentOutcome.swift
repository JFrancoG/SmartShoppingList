enum ShoppingIntentOutcome: Equatable {
    case added(storeName: String)
    case savedToDraft
    case alreadyProcessed
}
