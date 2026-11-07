import Foundation
import SwiftUI

@main
struct DistributionDiagnosticsApp: App {
    @State private var viewModel: DistributionDiagnosticsViewModel

    var body: some Scene {
        WindowGroup {
            DistributionDiagnosticsView(viewModel: viewModel)
        }
    }
}

extension DistributionDiagnosticsApp {
    init() {
        let probe = AppTransactionProbe()
        _viewModel = State(initialValue: DistributionDiagnosticsViewModel(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—",
            read: { await probe.read() }
        ))
    }
}
