#if DEBUG
import SwiftUI
import Observation

/// Isolated presentation diagnostics: no app factory, persistence, credentials or network.
struct ShoppingNoticeValidationView: View {
    @State private var model = ShoppingNoticeValidationModel()

    var body: some View {
        Form {
            Text(verbatim: "DEBUG · Notice validation")
                .font(.headline)
            Button {
                model.showStorage()
            } label: {
                Text(verbatim: "1. Storage notice")
            }
            Button {
                model.startReplacement()
            } label: {
                Text(verbatim: "2. Replace while open")
            }
            Text(verbatim: "For test 2, leave the first alert open for at least 5 seconds, then dismiss it. A second alert must appear.")
            Button {
                model.startVisibilityCycle()
            } label: {
                Text(verbatim: "3. Hide presenter while open")
            }
            Text(verbatim: "Run test 3 after test 2 or a fresh launch. Do not dismiss: the alert hides after 5 seconds. Then restore the presenter below.")
            if !model.isEnabled {
                Button {
                    model.restorePresenter()
                } label: {
                    Text(verbatim: "Restore presenter")
                }
            }
            Text(verbatim: model.diagnosticStatus)
        }
        .modifier(ShoppingNoticeModifier(notice: model.notice, isEnabled: model.isEnabled, dismiss: model.dismiss))
        .task(id: model.runID) {
            await model.runScenario()
        }
    }
}

@Observable @MainActor
private final class ShoppingNoticeValidationModel {
    private enum Scenario {
        case storage, replacement, visibilityCycle
    }

    private(set) var notice: ShoppingNotice?
    private(set) var runID = 0
    private(set) var isEnabled = true
    private var scenario = Scenario.storage
    private var replacementDelivered = false
    private var dismissedMessage = "none"

    var diagnosticStatus: String {
        "Presenter enabled: \(isEnabled). Replacement delivered: \(replacementDelivered). Last dismissed: \(dismissedMessage). Pending: \(notice.map { String(localized: $0.message) } ?? "none")"
    }

    func showStorage() {
        scenario = .storage
        isEnabled = true
        runID += 1
        notice = Self.storageNotice
    }

    func startReplacement() {
        replacementDelivered = false
        dismissedMessage = "none"
        scenario = .replacement
        isEnabled = true
        runID += 1
        notice = ShoppingNotice(
            source: .draft,
            message: "The text could not be interpreted. Your draft is kept; you can retry or continue manually."
        )
    }

    func startVisibilityCycle() {
        scenario = .visibilityCycle
        isEnabled = true
        replacementDelivered = false
        dismissedMessage = "none"
        runID += 1
        notice = Self.storageNotice
    }

    func runScenario() async {
        let currentScenario = scenario
        let currentRunID = runID
        guard currentScenario != .storage else { return }
        do {
            try await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, runID == currentRunID else { return }
            switch currentScenario {
            case .storage:
                return
            case .replacement:
                replacementDelivered = true
                notice = ShoppingNotice(
                    source: .draft,
                    message: "No products were found. You can rephrase the text or add them manually."
                )
            case .visibilityCycle:
                isEnabled = false
            }
        } catch {
            return
        }
    }

    func restorePresenter() {
        isEnabled = true
    }

    func dismiss(_ snapshot: ShoppingNotice) {
        dismissedMessage = String(localized: snapshot.message)
        guard snapshot.source != .storage, notice == snapshot else { return }
        notice = nil
    }

    private static let storageNotice = ShoppingNotice(
        source: .storage,
        message: "The saved draft could not be restored. It is kept unchanged. Changes in this session will not be saved when you close the app."
    )
}

#Preview {
    ShoppingNoticeValidationView()
}
#endif
