#if DEBUG
import SwiftUI

/// Isolated asset swatches; no application services or user data are constructed.
struct DesignSystemPreview: View {
    @ScaledMetric(relativeTo: .body) private var swatchHeight = 44

    private let colors: [(name: String, color: Color)] = [
        ("canvas", .canvas),
        ("surface", .surface),
        ("surface-muted", .surfaceMuted),
        ("text-primary", .textPrimary),
        ("text-secondary", .textSecondary),
        ("text-tertiary", .textTertiary),
        ("primary", .appPrimary),
        ("on-primary", .onPrimary),
        ("primary-soft", .primarySoft),
        ("success", .success),
        ("success-soft", .successSoft),
        ("warning", .warning),
        ("warning-soft", .warningSoft),
        ("danger", .danger),
        ("danger-soft", .dangerSoft),
        ("info", .info),
        ("info-soft", .infoSoft),
        ("border", .border),
        ("separator", .appSeparator),
        ("brand-yellow", .brandYellow),
        ("on-yellow", .onYellow)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 136))], spacing: 16) {
                ForEach(colors, id: \.name) { swatch in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(swatch.color)
                            .frame(height: swatchHeight)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(.border, lineWidth: 1)
                            }
                        Text(verbatim: swatch.name)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
        }
        .background(.canvas)
    }
}

#Preview("Semantic colors", traits: .fixedLayout(width: 500, height: 950)) {
    DesignSystemPreview()
}
#endif
