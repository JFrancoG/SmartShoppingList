#if DEBUG
import Observation
import SwiftUI

/// Real deletion screens backed only by synthetic, in-memory preview services.
struct ShoppingAccountDeletionValidationView: View {
    @State private var model = ShoppingAccountDeletionValidationModel()

    var body: some View {
        Group {
            if let shopping = model.shopping {
                if model.showsSettings {
                    SharedSettingsView(viewModel: shopping)
                } else {
                    NavigationStack {
                        SharedAccountDeletionView(viewModel: shopping)
                    }
                }
            } else if let failure = model.failure {
                Text(verbatim: failure)
            } else {
                ProgressView()
            }
        }
        .environment(\.usesPreparedShoppingPreview, true)
        .environment(\.locale, Locale(identifier: "es"))
        .environment(\.dynamicTypeSize, model.textSize)
        .task { await model.prepare() }
    }
}

@Observable @MainActor
private final class ShoppingAccountDeletionValidationModel {
    private enum Scenario: String {
        case prepared, authorized, pending, completed
    }

    private(set) var shopping: SharedShoppingViewModel?
    private(set) var failure: String?
    let textSize: DynamicTypeSize
    private let scenario: Scenario
    var showsSettings: Bool { scenario == .pending }

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        scenario = Self.value(after: "-shopping-deletion-state", in: arguments).flatMap(Scenario.init(rawValue:))
            ?? .prepared
        textSize = switch Self.value(after: "-shopping-deletion-text-size", in: arguments) {
        case "XXXLarge": .xxxLarge
        case "AX5": .accessibility5
        default: .large
        }
    }

    func prepare() async {
        guard shopping == nil, failure == nil else { return }
        do {
            let fixture = try SharedPreviewFixture.sample()
            let state: SharedPreviewState = scenario == .pending || scenario == .completed ? .deletionPending : .group
            let model = SharedPreviewSupport.viewModel(fixture: fixture, state: state)
            await SharedPreviewSupport.prepare(model, fixture: fixture, state: state)
            model.accountDeletion.preparePreview(
                completed: scenario == .completed,
                awaitingCompletion: scenario == .pending,
                authorized: scenario == .authorized
            )
            shopping = model
        } catch {
            failure = "DEBUG fixture could not be prepared: \(error)"
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

#Preview(traits: .sharedShopping) {
    ShoppingAccountDeletionValidationView()
}
#endif
