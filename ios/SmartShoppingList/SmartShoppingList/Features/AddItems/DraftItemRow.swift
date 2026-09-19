import SwiftUI

struct DraftItemRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var sectionSpacing: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var detailSpacing: CGFloat = 4
    @ScaledMetric(relativeTo: .body) private var verticalPadding: CGFloat = 4

    let item: ShoppingDraftItem
    let onEdit: () -> Void
    let onRemove: () -> Void

    private var actionsLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            AnyLayout(VStackLayout(alignment: .leading, spacing: sectionSpacing))
        } else {
            AnyLayout(HStackLayout())
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            VStack(alignment: .leading, spacing: detailSpacing) {
                if item.name.isEmpty {
                    Text("Producto sin nombre")
                        .font(.headline)
                } else {
                    Text(item.name)
                        .font(.headline)
                }

                if item.quantity.isEmpty {
                    Text("Cantidad no indicada")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Cantidad: \(item.quantity)")
                        .foregroundStyle(.secondary)
                }

                if item.store.isEmpty {
                    Label("Indica una tienda", systemImage: "exclamationmark.circle")
                } else {
                    Label(item.store, systemImage: "storefront")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)

            actionsLayout {
                Button("Editar", systemImage: "pencil") {
                    onEdit()
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Editar \(item.name)")
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer()
                }
                Button("Quitar", systemImage: "trash", role: .destructive) {
                    onRemove()
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Quitar \(item.name)")
            }
            .buttonStyle(.borderless)
        }
        .lineLimit(nil)
        .padding(.vertical, verticalPadding)
    }
}

#Preview(traits: .shoppingDraft) {
    Form {
        DraftItemRow(item: DraftPreviewSupport.items[0]) {} onRemove: {}
    }
}
