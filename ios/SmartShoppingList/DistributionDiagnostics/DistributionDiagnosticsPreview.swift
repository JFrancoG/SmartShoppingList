#if DEBUG
import SwiftUI

struct DistributionDiagnosticsPreview: PreviewModifier {
    static func makeSharedContext() async throws -> Void {}

    func body(content: Content, context: Void) -> some View {
        content
    }

    @MainActor
    static func makeViewModel(_ observation: AppTransactionObservation?) -> DistributionDiagnosticsViewModel {
        DistributionDiagnosticsViewModel(version: "1.0", build: "preview", observation: observation) {
            .verified(.sandbox)
        }
    }

    @MainActor
    static func makeLoadingViewModel() -> DistributionDiagnosticsViewModel {
        let viewModel = DistributionDiagnosticsViewModel(version: "1.0", build: "preview") {
            try? await Task.sleep(for: .seconds(3_600))
            return .cancelled
        }
        viewModel.requestCheck()
        return viewModel
    }
}
#endif
