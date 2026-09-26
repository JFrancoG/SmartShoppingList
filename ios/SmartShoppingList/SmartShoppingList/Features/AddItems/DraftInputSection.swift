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
            if viewModel.showsShoppingText {
                TextField("For example: bread at Aldi", text: $viewModel.shoppingText, axis: .vertical)
                    .lineLimit(2...)
                    .accessibilityLabel("Shopping text")
                    .disabled(isDictating || !viewModel.hasLoaded)
                    .listRowBackground(Color.surface)
            }

            switch viewModel.activity {
            case .idle:
                Button("Dictate", systemImage: "mic") {
                    viewModel.startDictation(replacingText: true)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(ShoppingIconButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(!viewModel.hasLoaded)
                if viewModel.showsShoppingText, viewModel.canInterpret {
                    Button("Interpret text", systemImage: "sparkles") {
                        viewModel.interpretText()
                    }
                    .buttonStyle(ShoppingActionButtonStyle())
                }
            case .interpreting:
                ProgressView("Interpreting text…")
                    .frame(maxWidth: .infinity)
                Button("Cancel interpretation", role: .cancel) {
                    viewModel.cancelInterpretation()
                }
                .buttonStyle(ShoppingActionButtonStyle())
            case .preparingSpeech:
                ProgressView("Preparing dictation…")
                    .frame(maxWidth: .infinity)
                Button("Cancel dictation", role: .cancel) {
                    viewModel.cancelDictation()
                }
                .buttonStyle(ShoppingActionButtonStyle())
            case .recording:
                Label("Listening…", systemImage: "waveform")
                    .frame(maxWidth: .infinity)
                Button("Finish dictation", systemImage: "stop.fill") {
                    viewModel.finishDictation()
                }
                .buttonStyle(ShoppingActionButtonStyle())
                Button("Cancel dictation", role: .cancel) {
                    viewModel.cancelDictation()
                }
                .buttonStyle(ShoppingActionButtonStyle())
            case .finishingSpeech:
                ProgressView("Finishing dictation…")
                    .frame(maxWidth: .infinity)
                Button("Cancel dictation", role: .cancel) {
                    viewModel.cancelDictation()
                }
                .buttonStyle(ShoppingActionButtonStyle())
            }
        } header: {
            Text("What would you like to add?")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.textPrimary)
                .textCase(nil)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

#Preview("Available model - ready") {
    @Previewable @State var viewModel = DraftPreviewSupport.viewModel(
        snapshot: ShoppingDraftSnapshot(),
        state: .availableModel
    )
    Form {
        DraftInputSection(viewModel: viewModel)
    }
    .modifier(ShoppingFormStyle())
}

#Preview("Available model - recovery", traits: .shoppingDraft(.availableModel)) {
    @Previewable @Environment(ShoppingDraftViewModel.self) var viewModel
    Form {
        DraftInputSection(viewModel: viewModel)
    }
    .modifier(ShoppingFormStyle())
}
