import SwiftUI

struct DraftInputSection: View {
    @Bindable var viewModel: ShoppingDraftViewModel

    private var isDictating: Bool {
        switch viewModel.activity {
        case .preparingSpeech, .recording, .finishingSpeech: true
        case .idle, .interpreting: false
        }
    }

    var body: some View {
        Section {
            TextField("Por ejemplo: jabón, cerveza y yogures en Mercadona", text: $viewModel.text, axis: .vertical)
                .lineLimit(3...)
                .accessibilityLabel("Texto de la compra")
                .disabled(isDictating || !viewModel.hasLoaded)

            switch viewModel.activity {
            case .idle:
                Button("Dictar", systemImage: "mic") {
                    viewModel.startDictation()
                }
                .disabled(!viewModel.hasLoaded)
                Button("Interpretar texto", systemImage: "sparkles") {
                    viewModel.interpretText()
                }
                .disabled(!viewModel.canInterpret)
            case .interpreting:
                ProgressView("Interpretando el texto…")
                Button("Cancelar interpretación", role: .cancel) {
                    viewModel.cancelInterpretation()
                }
            case .preparingSpeech:
                ProgressView("Preparando el dictado…")
                Button("Cancelar dictado", role: .cancel) {
                    viewModel.cancelDictation()
                }
            case .recording:
                Label("Escuchando…", systemImage: "waveform")
                Button("Terminar dictado", systemImage: "stop.fill") {
                    viewModel.finishDictation()
                }
                Button("Cancelar dictado", role: .cancel) {
                    viewModel.cancelDictation()
                }
            case .finishingSpeech:
                ProgressView("Terminando el dictado…")
                Button("Cancelar dictado", role: .cancel) {
                    viewModel.cancelDictation()
                }
            }

            if viewModel.availability != .available {
                Button("Comprobar disponibilidad") {
                    viewModel.refreshAvailability()
                }
                .disabled(viewModel.activity != .idle)
            }
        } header: {
            Text("Escribe o dicta")
        } footer: {
            Text(viewModel.availabilityMessage)
        }
    }
}

#Preview(traits: .shoppingDraft) {
    @Previewable @Environment(ShoppingDraftViewModel.self) var viewModel
    Form {
        DraftInputSection(viewModel: viewModel)
    }
}
