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
            TextField("For example: bread at Aldi", text: $viewModel.text, axis: .vertical)
                .lineLimit(3...)
                .accessibilityLabel("Shopping text")
                .disabled(isDictating || !viewModel.hasLoaded)

            switch viewModel.activity {
            case .idle:
                Button("Dictate", systemImage: "mic") {
                    viewModel.startDictation()
                }
                .disabled(!viewModel.hasLoaded)
                Button("Interpret text", systemImage: "sparkles") {
                    viewModel.interpretText()
                }
                .disabled(!viewModel.canInterpret)
            case .interpreting:
                ProgressView("Interpreting text…")
                Button("Cancel interpretation", role: .cancel) {
                    viewModel.cancelInterpretation()
                }
            case .preparingSpeech:
                ProgressView("Preparing dictation…")
                Button("Cancel dictation", role: .cancel) {
                    viewModel.cancelDictation()
                }
            case .recording:
                Label("Listening…", systemImage: "waveform")
                Button("Finish dictation", systemImage: "stop.fill") {
                    viewModel.finishDictation()
                }
                Button("Cancel dictation", role: .cancel) {
                    viewModel.cancelDictation()
                }
            case .finishingSpeech:
                ProgressView("Finishing dictation…")
                Button("Cancel dictation", role: .cancel) {
                    viewModel.cancelDictation()
                }
            }

            if viewModel.availability != .available {
                Button("Check availability") {
                    viewModel.refreshAvailability()
                }
                .disabled(viewModel.activity != .idle)
            }
        } header: {
            Text("Type or dictate")
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
