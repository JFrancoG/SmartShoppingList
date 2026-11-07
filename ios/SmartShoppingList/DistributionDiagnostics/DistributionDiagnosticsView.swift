import SwiftUI

struct DistributionDiagnosticsView: View {
    let viewModel: DistributionDiagnosticsViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Build") {
                    LabeledContent("Version", value: viewModel.version)
                    LabeledContent("Build number", value: viewModel.build)
                }
                Section {
                    LabeledContent("Verification") {
                        Text(viewModel.status)
                    }
                    LabeledContent("Environment") {
                        if let environment = viewModel.environment {
                            Text(verbatim: environment)
                                .textSelection(.enabled)
                        } else {
                            Text("Not determined")
                        }
                    }
                    if viewModel.isChecking {
                        ProgressView("Checking…")
                    }
                    Button("Check app transaction") {
                        viewModel.requestCheck()
                    }
                    .disabled(viewModel.isChecking)
                } header: {
                    Text("App transaction")
                } footer: {
                    Text("Reads the signed app transaction from Apple. This does not validate purchases or Premium access.")
                }
                Section {
                    Text("Diagnostic build. Your shopping lists and subscription are not accessed.")
                    Text("If the result is unavailable or unverified, record it and retry manually. No environment is assumed.")
                }
            }
            .navigationTitle("Diagnostics")
            .task(id: viewModel.requestCount) {
                await viewModel.checkIfRequested()
            }
        }
    }
}

#if DEBUG
#Preview("Verified Sandbox", traits: .modifier(DistributionDiagnosticsPreview())) {
    DistributionDiagnosticsView(viewModel: DistributionDiagnosticsPreview.makeViewModel(.verified(.sandbox)))
}

#Preview("Unavailable", traits: .modifier(DistributionDiagnosticsPreview())) {
    DistributionDiagnosticsView(viewModel: DistributionDiagnosticsPreview.makeViewModel(.unavailable))
}

#Preview("Not checked", traits: .modifier(DistributionDiagnosticsPreview())) {
    DistributionDiagnosticsView(viewModel: DistributionDiagnosticsPreview.makeViewModel(nil))
}

#Preview("Checking", traits: .modifier(DistributionDiagnosticsPreview())) {
    DistributionDiagnosticsView(viewModel: DistributionDiagnosticsPreview.makeLoadingViewModel())
}
#endif
